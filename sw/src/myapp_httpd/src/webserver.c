/* SPDX-License-Identifier: MIT */
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <zephyr/kernel.h>
#include <zephyr/data/json.h>
#include <zephyr/net/http/server.h>
#include <zephyr/net/http/service.h>
#include <zephyr/net/socket.h>
#include <zephyr/net/websocket.h>
#include <zephyr/sys/atomic.h>
#include <zephyr/sys/fdtable.h>
#include <zephyr/version.h>
#include "led.h"
#include "live_data.h"
#include "webserver.h"

static atomic_t stream_enabled = ATOMIC_INIT(1);
static atomic_t ws_active;
static atomic_t sent_frames;
static atomic_t send_errors;
K_MSGQ_DEFINE(ws_queue, sizeof(int), 1, sizeof(int));

/* These buffers must outlive their HTTP transactions / WebSocket session. */
static uint8_t ws_parse_buffer[256];
static uint8_t tx_frame[LIVE_MAX_MESSAGE_SIZE];
static const uint8_t index_html[] = {
#include <dashboard/index.html.gz.inc>
};
static const uint8_t app_css[] = {
#include <dashboard/app.css.gz.inc>
};
static const uint8_t dsp_js[] = {
#include <dashboard/dsp.js.gz.inc>
};
static const uint8_t app_js[] = {
#include <dashboard/app.js.gz.inc>
};

#define STATIC_RESOURCE(name, bytes, mime) \
    static struct http_resource_detail_static name = { \
        .common = { .type = HTTP_RESOURCE_TYPE_STATIC, \
            .bitmask_of_supported_http_methods = BIT(HTTP_GET), \
            .content_encoding = "gzip", .content_type = mime }, \
        .static_data = bytes, .static_data_len = sizeof(bytes), \
    }
STATIC_RESOURCE(index_detail, index_html, "text/html; charset=utf-8");
STATIC_RESOURCE(css_detail, app_css, "text/css; charset=utf-8");
STATIC_RESOURCE(js_detail, app_js, "text/javascript; charset=utf-8");
STATIC_RESOURCE(dsp_detail, dsp_js, "text/javascript; charset=utf-8");

struct dashboard_status {
    const char *device;
    const char *board;
    const char *zephyr;
    const char *built;
    const char *source;
    uint64_t uptime_ms;
    uint64_t frame_age_ms;
    uint32_t sequence;
    uint32_t frames;
    uint32_t channels;
    uint32_t max_frames;
    uint32_t sample_rate_hz;
    uint32_t update_rate_hz;
    uint32_t dropped;
    uint32_t sent;
    uint32_t send_errors;
    uint32_t ws_clients;
    bool stream_enabled;
    bool led1;
    bool led1_ready;
    bool has_frame;
};
#define STATUS_FIELD(field, tok) JSON_OBJ_DESCR_PRIM(struct dashboard_status, field, tok)
static const struct json_obj_descr status_descr[] = {
    STATUS_FIELD(device, JSON_TOK_STRING), STATUS_FIELD(board, JSON_TOK_STRING),
    STATUS_FIELD(zephyr, JSON_TOK_STRING), STATUS_FIELD(built, JSON_TOK_STRING),
    STATUS_FIELD(source, JSON_TOK_STRING), STATUS_FIELD(uptime_ms, JSON_TOK_UINT64),
    STATUS_FIELD(frame_age_ms, JSON_TOK_UINT64), STATUS_FIELD(sequence, JSON_TOK_UINT),
    STATUS_FIELD(frames, JSON_TOK_UINT), STATUS_FIELD(channels, JSON_TOK_UINT),
    STATUS_FIELD(max_frames, JSON_TOK_UINT), STATUS_FIELD(sample_rate_hz, JSON_TOK_UINT),
    STATUS_FIELD(update_rate_hz, JSON_TOK_UINT), STATUS_FIELD(dropped, JSON_TOK_UINT),
    STATUS_FIELD(sent, JSON_TOK_UINT), STATUS_FIELD(send_errors, JSON_TOK_UINT),
    STATUS_FIELD(ws_clients, JSON_TOK_UINT), STATUS_FIELD(stream_enabled, JSON_TOK_TRUE),
    STATUS_FIELD(led1, JSON_TOK_TRUE), STATUS_FIELD(led1_ready, JSON_TOK_TRUE),
    STATUS_FIELD(has_frame, JSON_TOK_TRUE),
};
#undef STATUS_FIELD

static const struct http_header no_cache[] = { { "Cache-Control", "no-store" } };

static void reply(struct http_response_ctx *response, enum http_status status,
                  const char *body)
{
    response->status = status;
    response->headers = no_cache;
    response->header_count = ARRAY_SIZE(no_cache);
    response->body = (const uint8_t *)body;
    response->body_len = strlen(body);
    response->final_chunk = true;
}

/* Zephyr 4.3.0 callback API, deliberately not the later transaction-status API. */
static int status_handler(struct http_client_ctx *client, enum http_data_status status,
                          const struct http_request_ctx *request,
                          struct http_response_ctx *response, void *user_data)
{
    ARG_UNUSED(client); ARG_UNUSED(request); ARG_UNUSED(user_data);
    static char body[1024];
    if (status != HTTP_SERVER_DATA_FINAL) {
        return 0;
    }
    struct live_stats live;
    live_data_get_stats(&live);
    struct dashboard_status s = {
        .device = CONFIG_APP_DEVICE_NAME,
        .board = CONFIG_BOARD_TARGET,
        .zephyr = KERNEL_VERSION_STRING,
        .built = __DATE__ " " __TIME__,
        .source = live.source == LIVE_SOURCE_DEMO ? "demo" :
                  live.source == LIVE_SOURCE_SENSOR ? "sensor" : "none",
        .uptime_ms = (uint64_t)k_uptime_get(),
        .frame_age_ms = live.source != LIVE_SOURCE_NONE ?
                        (uint64_t)k_uptime_get() - live.published_at_ms : 0,
        .sequence = live.sequence, .frames = live.frames,
        .channels = LIVE_CHANNELS, .max_frames = CONFIG_APP_LIVE_FRAMES,
        .sample_rate_hz = live.sample_rate_hz,
        .update_rate_hz = CONFIG_APP_LIVE_RATE_HZ,
        .dropped = live.dropped,
        .sent = (uint32_t)atomic_get(&sent_frames),
        .send_errors = (uint32_t)atomic_get(&send_errors),
        .ws_clients = (uint32_t)atomic_get(&ws_active),
        .stream_enabled = atomic_get(&stream_enabled) != 0,
        .led1 = led1_is_on(), .led1_ready = led1_is_ready(),
        .has_frame = live.source != LIVE_SOURCE_NONE,
    };
    int ret = json_obj_encode_buf(status_descr, ARRAY_SIZE(status_descr),
                                  &s, body, sizeof(body));
    if (ret < 0) {
        reply(response, HTTP_500_INTERNAL_SERVER_ERROR, "{\"error\":\"status too large\"}");
    } else {
        reply(response, HTTP_200_OK, body);
    }
    return 0;
}

struct enabled_command { bool enabled; };
static const struct json_obj_descr enabled_descr[] = {
    JSON_OBJ_DESCR_PRIM(struct enabled_command, enabled, JSON_TOK_TRUE),
};
struct control_context {
    char body[128];
    size_t used;
    bool overflow;
    bool is_led;
};
static struct control_context led_context = { .is_led = true };
static struct control_context stream_context;

static int control_handler(struct http_client_ctx *client, enum http_data_status status,
                           const struct http_request_ctx *request,
                           struct http_response_ctx *response, void *user_data)
{
    ARG_UNUSED(client);
    struct control_context *ctx = user_data;
    if (status == HTTP_SERVER_DATA_ABORTED) {
        ctx->used = 0;
        ctx->overflow = false;
        return 0;
    }
    /* Request bodies may be split across TCP packets / HTTP callbacks. */
    if (request->data_len > sizeof(ctx->body) - 1 - ctx->used) {
        ctx->overflow = true;
    } else if (!ctx->overflow && request->data_len != 0) {
        memcpy(ctx->body + ctx->used, request->data, request->data_len);
        ctx->used += request->data_len;
    }
    if (status != HTTP_SERVER_DATA_FINAL) {
        return 0;
    }
    ctx->body[ctx->used] = '\0';
    struct enabled_command command = {0};
    int parsed = ctx->overflow ? -E2BIG :
                 json_obj_parse(ctx->body, ctx->used, enabled_descr,
                                ARRAY_SIZE(enabled_descr), &command);
    if (ctx->overflow) {
        reply(response, HTTP_413_PAYLOAD_TOO_LARGE, "{\"error\":\"body exceeds 127 bytes\"}");
    } else if (parsed != BIT(0)) {
        reply(response, HTTP_400_BAD_REQUEST, "{\"error\":\"expected enabled boolean\"}");
    } else if (ctx->is_led && led1_set(command.enabled) < 0) {
        reply(response, HTTP_503_SERVICE_UNAVAILABLE, "{\"error\":\"LED1 GPIO unavailable\"}");
    } else {
        if (!ctx->is_led) {
            atomic_set(&stream_enabled, command.enabled);
        }
        reply(response, HTTP_200_OK, "{\"ok\":true}");
    }
    ctx->used = 0;
    ctx->overflow = false;
    return 0;
}

static int ws_setup(int socket, struct http_request_ctx *request, void *user_data)
{
    ARG_UNUSED(request); ARG_UNUSED(user_data);
    if (!atomic_cas(&ws_active, 0, 1)) {
        return -EBUSY;
    }
    /* Forwarded by the WebSocket fd to the underlying TCP socket. Without
     * O_NONBLOCK, Zephyr 4.3's sendmsg can outwait websocket_send_msg's timeout.
     */
    int flags = zsock_fcntl(socket, ZVFS_F_GETFL, 0);
    if (flags < 0 || zsock_fcntl(socket, ZVFS_F_SETFL, flags | ZVFS_O_NONBLOCK) < 0 ||
        k_msgq_put(&ws_queue, &socket, K_NO_WAIT) != 0) {
        atomic_clear(&ws_active);
        return -EIO;  /* HTTP server closes a rejected upgraded socket. */
    }
    return 0;
}

static bool ws_send(int socket, const uint8_t *data, size_t size,
                    enum websocket_opcode opcode)
{
    return websocket_send_msg(socket, data, size, opcode, false, true, 500) >= 0;
}

static bool ws_close_code(int socket, uint16_t code)
{
    uint8_t payload[2] = { code >> 8, code & 0xff };
    (void)ws_send(socket, payload, sizeof(payload), WEBSOCKET_OPCODE_CLOSE);
    return false;
}

struct rx_control { uint8_t bytes[125]; size_t used; };

static bool ws_receive(int socket, struct rx_control *rx)
{
    /* One byte at a time makes 4.3's parser always return valid type/remaining
     * metadata, even when the peer splits a control frame across TCP packets.
     * A short positive poll timeout also supports native_sim socket offload.
     * The total work per tick is bounded. Large client data is not accepted.
     */
    for (int i = 0; i < 128; i++) {
        uint8_t byte;
        uint32_t type = 0;
        uint64_t remaining = 0;
        int ret = websocket_recv_msg(socket, &byte, 1, &type, &remaining, 1);
        if (ret == -EAGAIN) {
            return true;
        }
        if (ret < 0 || (type & WEBSOCKET_FLAG_CLOSE)) {
            return false;
        }
        if (rx->used + ret + remaining > sizeof(rx->bytes)) {
            return ws_close_code(socket, 1009);
        }
        if (ret > 0) {
            rx->bytes[rx->used++] = byte;
        }
        if (remaining != 0) {
            continue;
        }
        bool ok = true;
        if (!(type & WEBSOCKET_FLAG_FINAL)) {
            return ws_close_code(socket, 1003);
        }
        if (type & WEBSOCKET_FLAG_PING) {
            ok = ws_send(socket, rx->bytes, rx->used, WEBSOCKET_OPCODE_PONG);
        } else if ((type & WEBSOCKET_FLAG_TEXT) && rx->used == 4 &&
                   memcmp(rx->bytes, "ping", 4) == 0) {
            ok = ws_send(socket, (const uint8_t *)"pong", 4, WEBSOCKET_OPCODE_DATA_TEXT);
        } else if (!(type & WEBSOCKET_FLAG_PONG)) {
            return ws_close_code(socket, 1003);
        }
        rx->used = 0;
        if (!ok) {
            return false;
        }
    }
    return true;
}

static void ws_worker(void *p1, void *p2, void *p3)
{
    ARG_UNUSED(p1); ARG_UNUSED(p2); ARG_UNUSED(p3);
    while (true) {
        int socket;
        k_msgq_get(&ws_queue, &socket, K_FOREVER);
        struct rx_control rx = {0};
        uint32_t last_sequence = 0;
        bool first = true;
        bool healthy = true;
        while (healthy) {
            int64_t start = k_uptime_get();
            healthy = ws_receive(socket, &rx);
            if (!healthy) {
                break;
            }
            if (atomic_get(&stream_enabled)) {
                size_t length;
                uint32_t sequence;
                int ret = live_data_copy(tx_frame, sizeof(tx_frame), &length, &sequence);
                if (ret == 0 && (first || sequence != last_sequence)) {
                    healthy = ws_send(socket, tx_frame, length, WEBSOCKET_OPCODE_DATA_BINARY);
                    if (healthy) {
                        atomic_inc(&sent_frames);
                        last_sequence = sequence;
                        first = false;
                    } else {
                        atomic_inc(&send_errors);
                    }
                }
            }
            int64_t delay = 1000 / CONFIG_APP_LIVE_RATE_HZ - (k_uptime_get() - start);
            k_sleep(K_MSEC(MAX(delay, 1)));
        }
        (void)websocket_unregister(socket);
        atomic_clear(&ws_active);
    }
}
K_THREAD_DEFINE(ws_thread, 4096, ws_worker, NULL, NULL, NULL, 9, 0, 0);

static struct http_resource_detail_dynamic status_detail = {
    .common = { .type = HTTP_RESOURCE_TYPE_DYNAMIC,
        .bitmask_of_supported_http_methods = BIT(HTTP_GET),
        .content_type = "application/json" },
    .cb = status_handler,
};
#define CONTROL_RESOURCE(name, ctx) \
    static struct http_resource_detail_dynamic name = { \
        .common = { .type = HTTP_RESOURCE_TYPE_DYNAMIC, \
            .bitmask_of_supported_http_methods = BIT(HTTP_POST), \
            .content_type = "application/json" }, \
        .cb = control_handler, .user_data = ctx, \
    }
CONTROL_RESOURCE(led_detail, &led_context);
CONTROL_RESOURCE(stream_detail, &stream_context);
static struct http_resource_detail_websocket live_detail = {
    .common = { .type = HTTP_RESOURCE_TYPE_WEBSOCKET,
        .bitmask_of_supported_http_methods = BIT(HTTP_GET) },
    .cb = ws_setup, .data_buffer = ws_parse_buffer,
    .data_buffer_len = sizeof(ws_parse_buffer),
};
static uint16_t http_port = CONFIG_APP_HTTP_PORT;
HTTP_SERVICE_DEFINE(dashboard, "0.0.0.0", &http_port,
                    CONFIG_HTTP_SERVER_MAX_CLIENTS, 4, NULL, NULL, NULL);
HTTP_RESOURCE_DEFINE(index_resource, dashboard, "/", &index_detail);
HTTP_RESOURCE_DEFINE(css_resource, dashboard, "/app.css", &css_detail);
HTTP_RESOURCE_DEFINE(js_resource, dashboard, "/app.js", &js_detail);
HTTP_RESOURCE_DEFINE(dsp_resource, dashboard, "/dsp.js", &dsp_detail);
HTTP_RESOURCE_DEFINE(status_resource, dashboard, "/api/status", &status_detail);
HTTP_RESOURCE_DEFINE(led_resource, dashboard, "/api/led", &led_detail);
HTTP_RESOURCE_DEFINE(stream_resource, dashboard, "/api/stream", &stream_detail);
HTTP_RESOURCE_DEFINE(live_resource, dashboard, "/ws/live", &live_detail);

int webserver_start(void)
{
    return http_server_start();
}