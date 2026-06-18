package com.poc.adapter;

import com.pingidentity.sdk.IdpAuthenticationAdapterV2;
import com.pingidentity.sdk.AuthnAdapterResponse;
import com.pingidentity.sdk.AuthnAdapterResponse.AUTHN_STATUS;
import com.pingidentity.sdk.IdpAuthenticationAdapterDescriptor;
import com.pingidentity.sdk.CheckAuthnStateResult;
import org.sourceid.saml20.adapter.conf.Configuration;
import org.sourceid.saml20.adapter.gui.AdapterConfigurationGuiDescriptor;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.time.Instant;
import java.util.*;
import java.util.logging.Logger;
import java.util.regex.Pattern;

public class ParValidationAdapter implements IdpAuthenticationAdapterV2 {

    private static final Logger LOG = Logger.getLogger(ParValidationAdapter.class.getName());

    private static final Set<String> CANAUX_AUTORISES = Set.of("web", "mobile", "api");
    private static final Pattern USERID_PATTERN = Pattern.compile("^[a-zA-Z0-9_\\-]{3,64}$");

    @Override
    public IdpAuthenticationAdapterDescriptor getAdapterDescriptor() {
        AdapterConfigurationGuiDescriptor guiDesc =
            new AdapterConfigurationGuiDescriptor("POC PAR Validation - sans configuration");

        return new IdpAuthenticationAdapterDescriptor(
            "PocParValidationAdapter",
            "POC PAR Validation Adapter",
            guiDesc,
            Collections.emptySet(),
            false
        );
    }

    @Override
    public void configure(Configuration configuration) {
    }

    @Override
    public AuthnAdapterResponse initiateAuthnRequest(
            HttpServletRequest request,
            HttpServletResponse response,
            Map<String, Object> inParameters) throws Exception {

        String canal  = getParam(request, inParameters, "canal");
        String userId = getParam(request, inParameters, "userId");

        LOG.info("[ParValidationAdapter] canal=" + canal + " userId=" + userId);

        String erreur = valider(canal, userId);
        if (erreur != null) {
            LOG.warning("[ParValidationAdapter] REJET : " + erreur);
            AuthnAdapterResponse rejet = new AuthnAdapterResponse();
            rejet.setAuthnStatus(AUTHN_STATUS.FAILURE);
            rejet.setErrorMessage("invalid_request: " + erreur);
            return rejet;
        }

        simulerPublicationKafka(canal, userId);

        AuthnAdapterResponse ok = new AuthnAdapterResponse();
        ok.setAuthnStatus(AUTHN_STATUS.SUCCESS);
        ok.setAttributeMap(Collections.emptyMap());
        return ok;
    }

    private String valider(String canal, String userId) {
        if (canal == null || canal.isBlank()) {
            return "parametre 'canal' absent";
        }
        if (canal.length() > 10) {
            return "parametre 'canal' trop long (" + canal.length() + " car., max 10)";
        }
        if (!CANAUX_AUTORISES.contains(canal.trim().toLowerCase())) {
            return "valeur 'canal' non autorisee : " + canal;
        }
        if (userId == null || userId.isBlank()) {
            return "parametre 'userId' absent";
        }
        if (!USERID_PATTERN.matcher(userId.trim()).matches()) {
            return "parametre 'userId' format invalide (3-64 car., alphanum/-/_)";
        }
        return null;
    }

    private void simulerPublicationKafka(String canal, String userId) {
        String event = "{"
            + "\"event_type\":\"par_attributes_validated\","
            + "\"canal\":\"" + canal + "\","
            + "\"userId\":\"" + userId + "\","
            + "\"timestamp\":\"" + Instant.now() + "\""
            + "}";

        System.out.println("[KAFKA SIMULATION] topic=pf.authn.events event=" + event);
    }

    @SuppressWarnings("unchecked")
    private String getParam(HttpServletRequest request,
                             Map<String, Object> inParameters,
                             String name) {
        Object additionalParams = inParameters.get("additionalAuthnParameters");
        if (additionalParams instanceof Map) {
            Object val = ((Map<String, Object>) additionalParams).get(name);
            if (val != null) return val.toString();
        }
        return request.getParameter(name);
    }

    @Override
    public AuthnAdapterResponse postAuthnStep(
            HttpServletRequest request, HttpServletResponse response,
            Map<String, Object> inParameters, String authnIdentifier) {
        return null;
    }

    @Override
    public boolean logoutAuthN(Map authnIdentifiers, HttpServletRequest req,
                                HttpServletResponse resp, String resumePath) {
        return false;
    }

    @Override
    public Map<String, Object> getAdapterInfo() {
        return Collections.emptyMap();
    }

    @Override
    public CheckAuthnStateResult checkAuthnState(HttpServletRequest req,
                                                  HttpServletResponse resp,
                                                  Map<String, Object> params) {
        return new CheckAuthnStateResult(false, null);
    }

    @Override
    public AuthnAdapterResponse resumeAuthnRequest(HttpServletRequest req,
                                                    HttpServletResponse resp,
                                                    Map<String, Object> params) {
        return null;
    }
                           }
