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

#include <zephyr/kernel.h>
#include <zephyr/sys/printk.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/sys/atomic.h>
#include <errno.h>
#include "led.h"

/* Get LED from devicetree */
#define LED0_NODE DT_ALIAS(led0)
#define LED1_NODE DT_ALIAS(led1)


#if !DT_NODE_HAS_STATUS(LED0_NODE, okay)
#error "No LED0 alias found in device tree"
#endif

#if !DT_NODE_HAS_STATUS(LED1_NODE, okay)
#error "No LED1 alias found in device tree"
#endif

static const struct gpio_dt_spec led0 = GPIO_DT_SPEC_GET(LED0_NODE, gpios);
static const struct gpio_dt_spec led1 = GPIO_DT_SPEC_GET(LED1_NODE, gpios);
static atomic_t led0_ready;
static atomic_t led1_ready;
static atomic_t led1_state;
K_MUTEX_DEFINE(led1_lock);

/* LED thread function */
void led_thread(void *arg1, void *arg2, void *arg3)
{


    while (1) {
        if (atomic_get(&led0_ready)) {
            gpio_pin_toggle_dt(&led0);
        }
        k_sleep(K_MSEC(50));
    }
}


void led1_on(void)
{
    (void)led1_set(true);
}

void led1_off(void)
{
    (void)led1_set(false);
}

int led1_set(bool enabled)
{
    if (!atomic_get(&led1_ready)) {
        return -ENODEV;
    }
    k_mutex_lock(&led1_lock, K_FOREVER);
    int ret = gpio_pin_set_dt(&led1, enabled);
    if (ret == 0) {
        atomic_set(&led1_state, enabled);
    }
    k_mutex_unlock(&led1_lock);
    return ret;
}

bool led1_is_on(void) { return atomic_get(&led1_state) != 0; }
bool led1_is_ready(void) { return atomic_get(&led1_ready) != 0; }

void init_leds(void)
{
    if (gpio_is_ready_dt(&led0) &&
        gpio_pin_configure_dt(&led0, GPIO_OUTPUT_INACTIVE) == 0) {
        atomic_set(&led0_ready, 1);
    } else {
        printk("LED0 device not ready\n");
    }
    if (gpio_is_ready_dt(&led1) &&
        gpio_pin_configure_dt(&led1, GPIO_OUTPUT_INACTIVE) == 0) {
        atomic_set(&led1_ready, 1);
    } else {
        printk("LED1 device not ready\n");
    }
}
