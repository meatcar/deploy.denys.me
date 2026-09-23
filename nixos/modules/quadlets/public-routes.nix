# Reviewed against usetrmnl/larapaper 0.37.1 routes/api.php and Invoice Ninja
# v5.13.29 routes/{client,vendor,contact,shop,web,api}.php, AppServiceProvider.php,
# portal templates and composer.lock (Livewire 3.8.3). Re-review on upgrades.
let
  read = "(Method(`GET`) || Method(`HEAD`))";
  submit = "(${read} || Method(`POST`))";
  uuid = "[0-9a-fA-F-]{36}";
  key = "[A-Za-z0-9._~-]+";
  vendorRead = "^/(vendors|vendor/(key_login/${key}|purchase_order/${key}(/download(_e_purchase_order)?)?|dashboard|purchase_orders(/${key})?|showBlob/${key}|logout|documents(/${key}(/download(_pdf)?)?)?))$";
  vendorPost = "^/vendor/(purchase_orders/bulk|purchase_order/upload/${key}|documents/download_multiple)$";
  vendorProfile = "^/vendor/profile/${key}/edit$";
in
{
  # nginx must pass these dynamic routes to Laravel before its /vendor/ asset
  # location. Share the paths so adding a public route cannot leave it static.
  invoiceninjaVendorPaths = [
    vendorRead
    vendorPost
    vendorProfile
  ];

  larapaper = builtins.concatStringsSep " || " [
    "(${read} && (Path(`/api/setup`) || Path(`/api/display`) || Path(`/api/current_screen`)))"
    "(Method(`POST`) && (Path(`/api/log`) || Path(`/api/screens`)))"
    "(${read} && PathRegexp(`^/storage/(images|firmwares)/.+$`))"
    # Existing public integrations use UUIDs, not the Sanctum admin routes.
    "((${read} || Method(`POST`)) && PathRegexp(`^/api/custom_plugins/${uuid}$`))"
    "(Method(`POST`) && PathRegexp(`^/api/(plugins/${uuid}/webhook|plugin_settings/${uuid}/image)$`))"
    "(${read} && PathRegexp(`^/api/display/${uuid}/alias$`))"
  ];

  invoiceninja = builtins.concatStringsSep " || " [
    # The client namespace contains no admin routes, including method-spoofed
    # forms. Upstream explicitly aborts its fallback for /client and /client/*.
    "Path(`/client`) || PathPrefix(`/client/`)"
    # Vendor invitation/key middleware and auth:vendor remain in Laravel.
    "(${read} && PathRegexp(`${vendorRead}`))"
    "(Method(`POST`) && PathRegexp(`${vendorPost}`))"
    # vendor_profile/edit.blade.php submits POST with _method=PUT and CSRF.
    "((${submit} || Method(`PUT`)) && PathRegexp(`${vendorProfile}`))"
    "(${submit} && Path(`/set_password`))"
    "(${read} && (Path(`/error`) || PathRegexp(`^/documents/${key}(/hashed)?$`)))"
    # Livewire is used by the customer portal, not the React admin application.
    "(Method(`POST`) && (Path(`/livewire/update`) || Path(`/livewire/upload-file`)))"
    "(${read} && (Path(`/livewire/livewire.js`) || Path(`/livewire/livewire.min.js`) || PathRegexp(`^/livewire/preview-file/[^/]+$`)))"
    "(Method(`POST`) && Path(`/api/v1/contact/login`))"
    "(${read} && Path(`/api/v1/contact/invoices`))"
    "(${read} && PathRegexp(`^/api/v1/shop/(products|profile|(client|invoice|product)/${key})$`))"
    "(Method(`POST`) && (Path(`/api/v1/shop/clients`) || Path(`/api/v1/shop/invoices`)))"
    "(${submit} && (Path(`/payments/process/response`) || PathRegexp(`^/payment_webhook/${key}/${key}$`) || PathRegexp(`^/payment_notification_webhook/${key}/${key}/${key}$`)))"
    "(${read} && PathRegexp(`^/(checkout/3ds_redirect|mollie/3ds_redirect|gocardless/ibp_redirect)/${key}/${key}/${key}$`))"
    "(${read} && Path(`/.well-known/apple-developer-merchantid-domain-association`))"
    # Inbound callbacks, not the admin APIs that configure these integrations.
    # SNS is deliberately absent; its dedicated exact-POST router is unchanged.
    "(Method(`POST`) && PathRegexp(`^/api/v1/(ppcp/webhook|postmark_webhook|postmark_inbound_webhook|mailgun_webhook|mailgun_inbound_webhook|brevo_webhook|brevo_inbound_webhook|process_webhook|yodlee/(refresh|data_updates|refresh_updates|balance))$`))"
    "(Method(`POST`) && Path(`/gocardless/oauth/connect/webhook`))"
    "(${read} && PathRegexp(`^/(stripe/completed|gocardless/oauth/connect/confirm|square/callback|quickbooks/authorized|calendar_connection/${key}/callback)$`))"
    # NOTE: v5.13.29 derives these shared OAuth login/callback URLs from APP_URL.
    "(${read} && (Path(`/auth/google`) || Path(`/auth/microsoft`)))"
    "Path(`/nordigen/confirm`)"
    # Only portal assets. nginx must return 404 for missing files, never invoke
    # Laravel's admin fallback. React's /assets, /react and /build-admin stay private.
    "(${read} && (PathRegexp(`^/(build|css|js|images|fonts|vendor|gateway-card-images|storage)/.+$`) || Path(`/favicon.ico`) || Path(`/favicon.png`) || Path(`/robots.txt`)))"
  ];
}
