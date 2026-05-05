package com.poc;

import com.pingidentity.sdk.GuiConfigDescriptor;
import com.pingidentity.sdk.PluginDescriptor;
import com.pingidentity.sdk.authorizationdetails.*;
import org.sourceid.saml20.adapter.conf.Configuration;
import java.util.Map;

public class BankingTransferProcessor implements AuthorizationDetailProcessor {

    @Override
    public void configure(Configuration configuration) {}

    @Override
    public PluginDescriptor getPluginDescriptor() {
        GuiConfigDescriptor gui = new GuiConfigDescriptor();
        return new AuthorizationDetailProcessorDescriptor(
            "Banking Transfer Processor", this, gui, "1.0"
        );
    }

    @Override
    public AuthorizationDetailValidationResult validate(
        AuthorizationDetail detail,
        AuthorizationDetailContext context,
        Map<String, Object> params) {

        Map<String, Object> fields = detail.getDetail();

        // Verifier que les champs obligatoires sont presents
        if (fields.get("iban") == null) {
            return AuthorizationDetailValidationResult.createInvalidResult("IBAN manquant");
        }
        if (fields.get("amount") == null) {
            return AuthorizationDetailValidationResult.createInvalidResult("Montant manquant");
        }
        if (fields.get("currency") == null) {
            return AuthorizationDetailValidationResult.createInvalidResult("Devise manquante");
        }

        return AuthorizationDetailValidationResult.createValidResult();
    }

    @Override
    public AuthorizationDetail enrich(
        AuthorizationDetail detail,
        AuthorizationDetailContext context,
        Map<String, Object> params) throws AuthorizationDetailProcessingException {
        return detail;
    }

    @Override
    public String getUserConsentDescription(
        AuthorizationDetail detail,
        AuthorizationDetailContext context,
        Map<String, Object> params) throws AuthorizationDetailProcessingException {

        Map<String, Object> fields = detail.getDetail();

        Object amount   = fields.get("amount");
        Object currency = fields.get("currency");
        Object label    = fields.get("label");
        Object iban     = fields.get("iban");

        String amountStr = "N/A";
        if (amount != null) {
            try {
                double euros = Double.parseDouble(amount.toString()) / 100.0;
                amountStr = String.format("%.2f", euros);
            } catch (NumberFormatException e) {
                amountStr = amount.toString();
            }
        }

        String ibanStr     = iban     != null ? iban.toString()     : "N/A";
        String currencyStr = currency != null ? currency.toString() : "EUR";
        String labelStr    = label    != null ? label.toString()    : "N/A";

        return String.format(
            "Virement de %s %s vers IBAN %s | Reference : %s",
            amountStr,
            currencyStr,
            ibanStr,
            labelStr
        );
    }

    @Override
    public boolean isEqualOrSubset(
        AuthorizationDetail requested,
        AuthorizationDetail accepted,
        AuthorizationDetailContext context,
        Map<String, Object> params) throws AuthorizationDetailProcessingException {

        Map<String, Object> req = requested.getDetail();
        Map<String, Object> acc = accepted.getDetail();

        // IBAN different → nouveau consentement obligatoire
        Object reqIban = req.get("iban");
        Object accIban = acc.get("iban");
        if (reqIban == null || !reqIban.equals(accIban)) {
            return false;
        }

        // Montant different → nouveau consentement obligatoire
        Object reqAmount = req.get("amount");
        Object accAmount = acc.get("amount");
        if (reqAmount == null || !reqAmount.equals(accAmount)) {
            return false;
        }

        // Currency differente → nouveau consentement obligatoire
        Object reqCurrency = req.get("currency");
        Object accCurrency = acc.get("currency");
        if (reqCurrency == null || !reqCurrency.equals(accCurrency)) {
            return false;
        }

        // Tout identique → grant reutilisable
        return true;
    }
}
