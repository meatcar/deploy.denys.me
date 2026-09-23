<?php
// Routing fixture, not Laravel or a provider emulator. Model the v5.13.29
// LoginController APP_URL callback and Socialite's one-use session state.
// Provider identity lookup, tokens, database writes and middleware stay upstream.
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
if ($path === '/login' || preg_match('#^/auth/(google|microsoft)$#', $path, $provider)) {
    session_name('invoice_session');
    session_set_cookie_params(['secure' => true, 'httponly' => true, 'samesite' => 'Lax', 'path' => '/']);
    session_start();
    if ($path === '/login') {
        echo 'front controller';
        exit;
    }
    if (isset($_GET['code'])) {
        $state = $_SESSION['state'] ?? '';
        unset($_SESSION['state']);
        if (!$state || !hash_equals($state, $_GET['state'] ?? '')) {
            http_response_code(400);
            echo 'invalid OAuth state';
            exit;
        }
        header('Location: https://billing.vpn.denys.me/#/settings/user_details/connect', true, 302);
        exit;
    }
    $_SESSION['state'] = bin2hex(random_bytes(20));
    $query = http_build_query([
        'redirect_uri' => 'https://billing.denys.me/auth/' . $provider[1],
        'state' => $_SESSION['state'],
    ]);
    header('Location: https://provider.invalid/authorize?' . $query, true, 302);
    exit;
}
if ($path === '/vendors' || str_starts_with($path, '/vendor/')) {
    // Observe what Laravel would receive after nginx's internal rewrite.
    header('Content-Type: application/json');
    echo json_encode([
        'uri' => $_SERVER['REQUEST_URI'],
        'method' => $_SERVER['REQUEST_METHOD'],
        'form' => $_POST,
    ]);
    exit;
}
echo 'front controller';
