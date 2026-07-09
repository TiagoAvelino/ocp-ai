package com.redhat.demo.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record RoutingRequest(
        @NotBlank @Size(min = 3, max = 2000) String text,
        String correlationId
) {
}
