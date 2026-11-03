package com.example.demo.controller;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Map;

import org.junit.jupiter.api.Test;

/**
 * Unit tests for HelloController.
 * The controller is created with 'new' (no Spring, no web server), so only the Java methods are tested.
 */
class HelloControllerUnitTest {

    private final HelloController controller = new HelloController();

    @Test
    void sayHello_returnsSuccessMessage() {
        assertThat(controller.sayHello())
                .isEqualTo(Map.of("message", "Hello! Spring Boot application is running successfully."));
    }

    @Test
    void newHello_returnsNewApplicationMessage() {
        assertThat(controller.newHello())
                .isEqualTo(Map.of("message", "NEW SPRING BOOT APPLICATION !!!"));
    }
}
