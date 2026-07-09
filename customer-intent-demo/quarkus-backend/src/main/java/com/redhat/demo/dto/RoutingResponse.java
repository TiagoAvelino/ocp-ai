package com.redhat.demo.dto;

public record RoutingResponse(
        String correlationId,
        String text,
        String predictedIntent,
        String department,
        String departmentDisplayName,
        double confidence,
        String decision,
        String modelVersion,
        String queue
) {
}
