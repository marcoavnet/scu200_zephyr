/* SPDX-License-Identifier: MIT */
#include <errno.h>
#include <string.h>
#include <zephyr/kernel.h>
#include <zephyr/sys/atomic.h>
#include <zephyr/sys/byteorder.h>
#include "live_data.h"

K_MUTEX_DEFINE(frame_lock);
static uint8_t latest[LIVE_MAX_MESSAGE_SIZE];
static size_t latest_length;
static struct live_stats latest_stats;
static atomic_t dropped;

int live_data_publish(const int16_t *samples, size_t nframes,
                      uint32_t sample_rate_hz, enum live_source source)
{
    if (samples == NULL || nframes < 2 || nframes > CONFIG_APP_LIVE_FRAMES ||
        (source != LIVE_SOURCE_DEMO && source != LIVE_SOURCE_SENSOR)) {
        return -EINVAL;
    }
    if (k_mutex_lock(&frame_lock, K_NO_WAIT) != 0) {
        atomic_inc(&dropped);
        return -EAGAIN;
    }

    latest_stats.sequence++;
    latest_stats.frames = nframes;
    latest_stats.sample_rate_hz = sample_rate_hz;
    latest_stats.published_at_ms = k_uptime_get();
    latest_stats.source = source;

    /* Explicit little-endian protocol; no C structure padding on the wire. */
    memcpy(latest, "ZLV1", 4);
    sys_put_le16(LIVE_HEADER_SIZE, latest + 4);
    sys_put_le16(LIVE_CHANNELS, latest + 6);
    sys_put_le32(nframes, latest + 8);
    sys_put_le32(sample_rate_hz, latest + 12);
    sys_put_le32(latest_stats.sequence, latest + 16);
    sys_put_le32(source == LIVE_SOURCE_DEMO ? 1U : 0U, latest + 20);
    sys_put_le64(latest_stats.published_at_ms, latest + 24);
    for (size_t i = 0; i < nframes * LIVE_CHANNELS; i++) {
        sys_put_le16((uint16_t)samples[i], latest + LIVE_HEADER_SIZE + i * 2);
    }
    latest_length = LIVE_HEADER_SIZE + nframes * LIVE_CHANNELS * 2;
    k_mutex_unlock(&frame_lock);
    return 0;
}

int live_data_copy(uint8_t *dst, size_t capacity, size_t *length, uint32_t *sequence)
{
    if (dst == NULL || length == NULL || sequence == NULL) {
        return -EINVAL;
    }
    if (k_mutex_lock(&frame_lock, K_MSEC(5)) != 0) {
        return -EAGAIN;
    }
    int ret = -ENODATA;
    if (latest_length > capacity) {
        ret = -ENOSPC;
    } else if (latest_length != 0) {
        memcpy(dst, latest, latest_length);
        *length = latest_length;
        *sequence = latest_stats.sequence;
        ret = 0;
    }
    k_mutex_unlock(&frame_lock);
    return ret;
}

void live_data_get_stats(struct live_stats *stats)
{
    k_mutex_lock(&frame_lock, K_FOREVER);
    *stats = latest_stats;
    k_mutex_unlock(&frame_lock);
    stats->dropped = (uint32_t)atomic_get(&dropped);
}
