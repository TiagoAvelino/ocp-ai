package com.redhat.demo.dto;

public record ModelPredictResponse(
        String text,
        String predictedIntent,
        String department,
        double confidence,
        String decision,
        String modelVersion
) {
}
