package com.redhat.demo.service;

import com.redhat.demo.dto.ModelPredictRequest;
import com.redhat.demo.dto.ModelPredictResponse;
import com.redhat.demo.dto.RoutingRequest;
import com.redhat.demo.dto.RoutingResponse;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.eclipse.microprofile.rest.client.inject.RestClient;
import org.jboss.logging.Logger;

import java.time.Duration;
import java.util.Map;
import java.util.UUID;

@ApplicationScoped
public class RoutingService {

    private static final Logger LOG = Logger.getLogger(RoutingService.class);

    private static final Map<String, String> DEPARTMENT_DISPLAY = Map.of(
            "cards-support", "Cards Support",
            "transfers-support", "Transfers Support",
            "security-identity", "Security and Identity",
            "atm-support", "ATM Support"
    );

    @Inject
    @RestClient
    com.redhat.demo.client.ModelServiceClient modelClient;

    @Inject
    MeterRegistry meterRegistry;

    @ConfigProperty(name = "model.service.timeout", defaultValue = "5s")
    Duration timeout;

    private final Counter routingRequests;
    private final Counter routingFailures;
    private final Counter humanReview;
    private final Timer routingLatency;

    @Inject
    public RoutingService(MeterRegistry registry) {
        routingRequests = registry.counter("routing_requests_total");
        routingFailures = registry.counter("routing_failures_total");
        humanReview = registry.counter("human_review_total");
        routingLatency = registry.timer("routing_latency_seconds");
    }

    public RoutingResponse route(RoutingRequest request) {
        routingRequests.increment();
        String correlationId = request.correlationId() != null && !request.correlationId().isBlank()
                ? request.correlationId()
                : UUID.randomUUID().toString();

        Timer.Sample sample = Timer.start();
        try {
            ModelPredictResponse prediction = modelClient.predict(new ModelPredictRequest(request.text()));
            String department = prediction.department();
            meterRegistry.counter("department_routing_total", "department", department).increment();

            if ("HUMAN_REVIEW".equals(prediction.decision())) {
                humanReview.increment();
            }

            RoutingResponse response = new RoutingResponse(
                    correlationId,
                    request.text(),
                    prediction.predictedIntent(),
                    department,
                    DEPARTMENT_DISPLAY.getOrDefault(department, department),
                    prediction.confidence(),
                    prediction.decision(),
                    prediction.modelVersion(),
                    resolveQueue(prediction.decision(), department)
            );

            LOG.infof(
                    "correlationId=%s intent=%s department=%s confidence=%.4f decision=%s modelVersion=%s",
                    correlationId,
                    prediction.predictedIntent(),
                    department,
                    prediction.confidence(),
                    prediction.decision(),
                    prediction.modelVersion()
            );
            return response;
        } catch (Exception ex) {
            routingFailures.increment();
            LOG.warnf(ex, "Falha ao chamar modelo; encaminhando para revisão humana correlationId=%s", correlationId);
            humanReview.increment();
            return new RoutingResponse(
                    correlationId,
                    request.text(),
                    "unknown",
                    "human-review",
                    "Human Review Queue",
                    0.0,
                    "HUMAN_REVIEW",
                    "fallback",
                    "human-review-queue"
            );
        } finally {
            sample.stop(routingLatency);
        }
    }

    private String resolveQueue(String decision, String department) {
        if ("HUMAN_REVIEW".equals(decision)) {
            return "human-review-queue";
        }
        return department + "-queue";
    }
}
