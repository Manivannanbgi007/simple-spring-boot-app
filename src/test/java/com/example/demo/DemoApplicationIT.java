package com.example.demo;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.resttestclient.autoconfigure.AutoConfigureRestTestClient;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.SpringBootTest.WebEnvironment;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.client.RestTestClient;

/**
 * Integration tests: start the whole application on a random free port (real embedded Tomcat)
 * and call it over HTTP, like a browser or the Jenkins smoke test does.
 * The random port means the tests also work while the deployed container is using port 8080.
 * Class names ending in 'IT' are run by the Maven failsafe plugin during 'mvnw verify', not 'mvnw test'.
 */
@SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT)
@AutoConfigureRestTestClient
class DemoApplicationIT {

    @Autowired
    private RestTestClient client;

    @Test
    void helloEndpoint_returnsSuccessMessageAsJson() {
        client.get().uri("/api/hello")
                .exchange()
                .expectStatus().isOk()
                .expectHeader().contentType(MediaType.APPLICATION_JSON)
                .expectBody()
                .jsonPath("$.message").isEqualTo("Hello! Spring Boot application is running successfully.");
    }

    @Test
    void newEndpoint_returnsNewMessageAsJson() {
        client.get().uri("/api/new")
                .exchange()
                .expectStatus().isOk()
                .expectHeader().contentType(MediaType.APPLICATION_JSON)
                .expectBody()
                .jsonPath("$.message").isEqualTo("NEW SPRING BOOT APPLICATION!");
    }

    @Test
    void healthEndpoint_reportsUp() {
        client.get().uri("/actuator/health")
                .exchange()
                .expectStatus().isOk()
                .expectBody()
                .jsonPath("$.status").isEqualTo("UP");
    }

    // application.yml exposes only 'health', so endpoints that reveal internal details must not be reachable
    @ParameterizedTest
    @ValueSource(strings = {"/actuator/env", "/actuator/beans", "/actuator/info", "/actuator/metrics"})
    void otherActuatorEndpoints_areNotExposed(String path) {
        client.get().uri(path)
                .exchange()
                .expectStatus().isNotFound();
    }

    @Test
    void unknownPath_returnsNotFound() {
        client.get().uri("/api/does-not-exist")
                .exchange()
                .expectStatus().isNotFound();
    }
}
