/******************************************************************************
 * Copyright (c) 2026 Marco Höfle, Avnet-Silica
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files to deal in the software
 * without restriction, including without limitation the rights to use, copy,
 * modify, merge, publish, distribute, sublicense, and/or sell copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
 ******************************************************************************/

/* SPDX-License-Identifier: MIT */
#include <zephyr/kernel.h>
#include "live_data.h"

#if defined(CONFIG_APP_DEMO_DATA)
/* Integer lookup avoids floating-point and libm on MicroBlaze V. */
static const int16_t sine[256] = {
    0, 589, 1178, 1766, 2352, 2938, 3522, 4103, 4682, 5258, 5832, 6401, 6967, 7528, 8085, 8637,
    9184, 9726, 10261, 10791, 11314, 11830, 12338, 12840, 13334, 13819, 14297, 14766, 15225, 15676, 16117, 16549,
    16971, 17382, 17783, 18173, 18552, 18920, 19277, 19622, 19955, 20276, 20585, 20882, 21166, 21437, 21696, 21941,
    22173, 22392, 22597, 22789, 22967, 23131, 23281, 23417, 23539, 23647, 23740, 23820, 23884, 23935, 23971, 23993,
    24000, 23993, 23971, 23935, 23884, 23820, 23740, 23647, 23539, 23417, 23281, 23131, 22967, 22789, 22597, 22392,
    22173, 21941, 21696, 21437, 21166, 20882, 20585, 20276, 19955, 19622, 19277, 18920, 18552, 18173, 17783, 17382,
    16971, 16549, 16117, 15676, 15225, 14766, 14297, 13819, 13334, 12840, 12338, 11830, 11314, 10791, 10261, 9726,
    9184, 8637, 8085, 7528, 6967, 6401, 5832, 5258, 4682, 4103, 3522, 2938, 2352, 1766, 1178, 589,
    0, -589, -1178, -1766, -2352, -2938, -3522, -4103, -4682, -5258, -5832, -6401, -6967, -7528, -8085, -8637,
    -9184, -9726, -10261, -10791, -11314, -11830, -12338, -12840, -13334, -13819, -14297, -14766, -15225, -15676, -16117, -16549,
    -16971, -17382, -17783, -18173, -18552, -18920, -19277, -19622, -19955, -20276, -20585, -20882, -21166, -21437, -21696, -21941,
    -22173, -22392, -22597, -22789, -22967, -23131, -23281, -23417, -23539, -23647, -23740, -23820, -23884, -23935, -23971, -23993,
    -24000, -23993, -23971, -23935, -23884, -23820, -23740, -23647, -23539, -23417, -23281, -23131, -22967, -22789, -22597, -22392,
    -22173, -21941, -21696, -21437, -21166, -20882, -20585, -20276, -19955, -19622, -19277, -18920, -18552, -18173, -17783, -17382,
    -16971, -16549, -16117, -15676, -15225, -14766, -14297, -13819, -13334, -12840, -12338, -11830, -11314, -10791, -10261, -9726,
    -9184, -8637, -8085, -7528, -6967, -6401, -5832, -5258, -4682, -4103, -3522, -2938, -2352, -1766, -1178, -589,
};
static int16_t samples[CONFIG_APP_LIVE_FRAMES * LIVE_CHANNELS];
static struct k_thread demo_thread;
K_THREAD_STACK_DEFINE(demo_stack, 2048);

static void demo_run(void *p1, void *p2, void *p3)
{
    ARG_UNUSED(p1); ARG_UNUSED(p2); ARG_UNUSED(p3);
    uint32_t phase = 0;
    while (true) {
        int64_t start = k_uptime_get();
        for (size_t i = 0; i < CONFIG_APP_LIVE_FRAMES; i++) {
            uint32_t p = (i * 1024U / CONFIG_APP_LIVE_FRAMES + phase) & 255U;
            samples[i * LIVE_CHANNELS] = sine[p];
            samples[i * LIVE_CHANNELS + 1] = sine[(p + 64U) & 255U];
            samples[i * LIVE_CHANNELS + 2] = sine[(p * 2U) & 255U];
            samples[i * LIVE_CHANNELS + 3] = p < 128U ? 20000 : -20000;
        }
        (void)live_data_publish(samples, CONFIG_APP_LIVE_FRAMES,
                               CONFIG_APP_DEMO_SAMPLE_RATE_HZ, LIVE_SOURCE_DEMO);
        phase = (phase + 1U) & 255U;
        int64_t delay = 1000 / CONFIG_APP_LIVE_RATE_HZ - (k_uptime_get() - start);
        k_sleep(K_MSEC(MAX(delay, 1)));
    }
}
#endif

void demo_data_start(void)
{
#if defined(CONFIG_APP_DEMO_DATA)
    k_thread_create(&demo_thread, demo_stack, K_THREAD_STACK_SIZEOF(demo_stack),
                    demo_run, NULL, NULL, NULL, 8, 0, K_NO_WAIT);
    k_thread_name_set(&demo_thread, "live_demo");
#endif
}
