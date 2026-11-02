package com.example.demo.controller;

import java.util.Map;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * REST controller that exposes a simple greeting endpoint.
 */
@RestController
@RequestMapping("/api")
public class HelloController {

    private static final String SUCCESS_MESSAGE = "Hello! Spring Boot application is running successfully.";

    /**
     * Handles GET /api/hello.
     * Spring automatically converts the returned Map into JSON: {"message": "..."}
     */
    @GetMapping("/hello")
    public Map<String, String> sayHello() {
        return Map.of("message", SUCCESS_MESSAGE);
    }
}
