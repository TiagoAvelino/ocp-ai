package com.redhat.demo.client;

import com.redhat.demo.dto.ModelPredictRequest;
import com.redhat.demo.dto.ModelPredictResponse;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.rest.client.inject.RegisterRestClient;

@Path("/predict")
@RegisterRestClient(configKey = "model-service")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public interface ModelServiceClient {

    @POST
    ModelPredictResponse predict(ModelPredictRequest request);
}
