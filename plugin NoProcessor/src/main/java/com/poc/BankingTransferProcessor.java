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

        System.out.println("=== VALIDATE CALLED ===");

        Map<String, Object> fields = detail.getDetail();
        System.out.println("VALIDATE fields : " + fields);

        if (fields.get("iban") == null) {
            System.out.println("VALIDATE INVALID : iban manquant");
            return AuthorizationDetailValidationResult
                .createInvalidResult("Champ iban manquant");
        }

        if (fields.get("amount") == null) {
            System.out.println("VALIDATE INVALID : amount manquant");
            return AuthorizationDetailValidationResult
                .createInvalidResult("Champ amount manquant");
        }

        if (fields.get("currency") == null) {
            System.out.println("VALIDATE INVALID : currency manquante");
            return AuthorizationDetailValidationResult
                .createInvalidResult("Champ currency manquant");
        }

        System.out.println("VALIDATE OK");
        return AuthorizationDetailValidationResult.createValidResult();
    }

    @Override
    public AuthorizationDetail enrich(
        AuthorizationDetail detail,
        AuthorizationDetailContext context,
        Map<String, Object> params) throws AuthorizationDetailProcessingException {

        System.out.println("=== ENRICH CALLED ===");
        System.out.println("ENRICH detail : " + detail.getDetail());
        return detail;
    }

    @Override
    public String getUserConsentDescription(
        AuthorizationDetail detail,
        AuthorizationDetailContext context,
        Map<String, Object> params) throws AuthorizationDetailProcessingException {

        System.out.println("=== GET_USER_CONSENT_DESCRIPTION CALLED ===");

        Map<String, Object> fields = detail.getDetail();

        Object amount   = fields.get("amount");
        Object currency = fields.get("currency");
        Object label    = fields.get("label");
        Object iban     = fields.get("iban");

        System.out.println("CONSENT DESC amount   : " + amount   + " type=" + (amount   != null ? amount.getClass().getName()   : "null"));
        System.out.println("CONSENT DESC currency : " + currency + " type=" + (currency != null ? currency.getClass().getName() : "null"));
        System.out.println("CONSENT DESC label    : " + label    + " type=" + (label    != null ? label.getClass().getName()    : "null"));
        System.out.println("CONSENT DESC iban     : " + iban     + " type=" + (iban     != null ? iban.getClass().getName()     : "null"));

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

        String result = String.format(
            "Virement de %s %s vers IBAN %s | Reference : %s",
            amountStr, currencyStr, ibanStr, labelStr
        );

        System.out.println("CONSENT DESC result : " + result);
        return result;
    }

    @Override
    public boolean isEqualOrSubset(
        AuthorizationDetail requested,
        AuthorizationDetail accepted,
        AuthorizationDetailContext context,
        Map<String, Object> params) throws AuthorizationDetailProcessingException {

        System.out.println("=== IS_EQUAL_OR_SUBSET CALLED ===");

        Map<String, Object> req = requested.getDetail();
        Map<String, Object> acc = accepted.getDetail();

        System.out.println("REQ full map : " + req);
        System.out.println("ACC full map : " + acc);

        // IBAN
        Object reqIbanObj = req.get("iban");
        Object accIbanObj = acc.get("iban");
        String reqIban = reqIbanObj != null ? reqIbanObj.toString() : "";
        String accIban = accIbanObj != null ? accIbanObj.toString() : "";
        System.out.println("REQ iban : " + reqIban + " type=" + (reqIbanObj != null ? reqIbanObj.getClass().getName() : "null"));
        System.out.println("ACC iban : " + accIban + " type=" + (accIbanObj != null ? accIbanObj.getClass().getName() : "null"));
        if (!reqIban.equals(accIban)) {
            System.out.println("IS_EQUAL_OR_SUBSET FALSE : iban different");
            return false;
        }

        // AMOUNT
        Object reqAmountObj = req.get("amount");
        Object accAmountObj = acc.get("amount");
        String reqAmount = reqAmountObj != null ? reqAmountObj.toString() : "";
        String accAmount = accAmountObj != null ? accAmountObj.toString() : "";
        System.out.println("REQ amount : " + reqAmount + " type=" + (reqAmountObj != null ? reqAmountObj.getClass().getName() : "null"));
        System.out.println("ACC amount : " + accAmount + " type=" + (accAmountObj != null ? accAmountObj.getClass().getName() : "null"));
        if (!reqAmount.equals(accAmount)) {
            System.out.println("IS_EQUAL_OR_SUBSET FALSE : amount different");
            return false;
        }

        // CURRENCY
        Object reqCurrencyObj = req.get("currency");
        Object accCurrencyObj = acc.get("currency");
        String reqCurrency = reqCurrencyObj != null ? reqCurrencyObj.toString() : "";
        String accCurrency = accCurrencyObj != null ? accCurrencyObj.toString() : "";
        System.out.println("REQ currency : " + reqCurrency + " type=" + (reqCurrencyObj != null ? reqCurrencyObj.getClass().getName() : "null"));
        System.out.println("ACC currency : " + accCurrency + " type=" + (accCurrencyObj != null ? accCurrencyObj.getClass().getName() : "null"));
        if (!reqCurrency.equals(accCurrency)) {
            System.out.println("IS_EQUAL_OR_SUBSET FALSE : currency differente");
            return false;
        }

        System.out.println("IS_EQUAL_OR_SUBSET TRUE : RAR identique");
        return true;
    }
}
