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
#ifndef LIVE_DATA_H
#define LIVE_DATA_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define LIVE_CHANNELS 4U
#define LIVE_HEADER_SIZE 32U
#define LIVE_MAX_MESSAGE_SIZE (LIVE_HEADER_SIZE + CONFIG_APP_LIVE_FRAMES * LIVE_CHANNELS * 2U)

enum live_source {
    LIVE_SOURCE_NONE = 0,
    LIVE_SOURCE_DEMO = 1,
    LIVE_SOURCE_SENSOR = 2,
};

struct live_stats {
    uint32_t sequence;
    uint32_t frames;
    uint32_t sample_rate_hz;
    uint32_t dropped;
    uint64_t published_at_ms;
    enum live_source source;
};

/*
 * Publish interleaved signed samples: CH0, CH1, CH2, CH3, CH0, ... .
 * nframes is the sample count PER CHANNEL, not the int16_t element count.
 * Called from ONE acquisition thread, never an ISR (uses a mutex). It copies
 * the data before returning; the caller may then reuse its buffer.
 * Returns 0, -EINVAL, or -EAGAIN if the snapshot is busy. It never waits for
 * a browser/socket. sample_rate_hz=0 means unknown. Source must be explicit.
 */
int live_data_publish(const int16_t *interleaved, size_t nframes,
                      uint32_t sample_rate_hz, enum live_source source);

/* Sender takes a stable copy; slow clients never retain the producer's lock. */
int live_data_copy(uint8_t *dst, size_t capacity, size_t *length, uint32_t *sequence);
void live_data_get_stats(struct live_stats *stats);
void demo_data_start(void);

#endif
