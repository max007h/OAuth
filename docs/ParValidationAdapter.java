package com.poc.adapter;

import com.pingidentity.sdk.IdpAuthenticationAdapterV2;
import com.pingidentity.sdk.AuthnAdapterResponse;
import com.pingidentity.sdk.AuthnAdapterResponse.AUTHN_STATUS;
import com.pingidentity.sdk.IdpAuthenticationAdapterDescriptor;
import org.sourceid.saml20.adapter.idp.authn.IdpAuthnAdapterDescriptor;
import org.sourceid.saml20.adapter.idp.authn.AuthnPolicy;
import org.sourceid.saml20.adapter.AuthnAdapterException;
import org.sourceid.saml20.adapter.conf.Configuration;
import org.sourceid.saml20.adapter.gui.AdapterConfigurationGuiDescriptor;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import javax.servlet.http.HttpSession;
import java.io.IOException;
import java.time.Instant;
import java.util.*;
import java.util.logging.Logger;
import java.util.regex.Pattern;

public class ParValidationAdapter implements IdpAuthenticationAdapterV2 {

    private static final Logger LOG = Logger.getLogger(ParValidationAdapter.class.getName());

    private static final Set<String> CANAUX_AUTORISES = Set.of("web", "mobile", "api");
    private static final Pattern USERID_PATTERN = Pattern.compile("^[a-zA-Z0-9_\\-]{3,64}$");

    @Override
    public IdpAuthnAdapterDescriptor getAdapterDescriptor() {
        return new IdpAuthnAdapterDescriptor(
            this,
            "POC PAR Validation Adapter",
            Collections.emptySet(),
            false,
            new AdapterConfigurationGuiDescriptor(),
            false
        );
    }

    @Override
    public void configure(Configuration configuration) {
    }

    @Override
    public Map lookupAuthN(HttpServletRequest req, HttpServletResponse resp,
                           String partnerSpEntityId, AuthnPolicy policy, String resumePath)
            throws AuthnAdapterException, IOException {
        return Collections.emptyMap();
    }

    @Override
    public boolean logoutAuthN(Map authnIdentifiers, HttpServletRequest req,
                               HttpServletResponse resp, String resumePath)
            throws AuthnAdapterException, IOException {
        return false;
    }

    @Override
    public AuthnAdapterResponse lookupAuthN(HttpServletRequest request,
                                            HttpServletResponse response,
                                            Map<String, Object> inParameters) {

        // 1. Priorité : inParameters (contexte PF, inclut les Tracked HTTP Parameters)
        String canal = null;
        String userId = null;

        if (inParameters != null) {
            Object c = inParameters.get("canal");
            Object u = inParameters.get("userId");
            canal  = (c != null) ? c.toString() : null;
            userId = (u != null) ? u.toString() : null;
        }

        // 2. Fallback : session HTTP
        if (canal == null || userId == null) {
            HttpSession session = request.getSession(false);
            if (session != null) {
                if (canal  == null) canal  = (String) session.getAttribute("canal");
                if (userId == null) userId = (String) session.getAttribute("userId");
            }
        }

        // 3. Fallback : paramètre HTTP direct
        if (canal  == null) canal  = request.getParameter("canal");
        if (userId == null) userId = request.getParameter("userId");

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

    @Override
    public Map<String, Object> getAdapterInfo() {
        return Collections.emptyMap();
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
}

