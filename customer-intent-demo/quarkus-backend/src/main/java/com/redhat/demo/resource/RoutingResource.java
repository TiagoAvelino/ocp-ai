package com.redhat.demo.resource;

import com.redhat.demo.dto.RoutingRequest;
import com.redhat.demo.dto.RoutingResponse;
import com.redhat.demo.service.RoutingService;

import jakarta.inject.Inject;
import jakarta.validation.Valid;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

@Path("/api/v1/routing")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class RoutingResource {

    @Inject
    RoutingService routingService;

    @POST
    public RoutingResponse route(@Valid RoutingRequest request) {
        return routingService.route(request);
    }
}
