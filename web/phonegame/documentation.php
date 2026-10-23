<?php
// Phone Game: the website calls this when the player opens /documentation.
// It leaves a request file; the server (phonegame-web.path) then plans the call. The phone rings once, ever.
header('Content-Type: application/json');
header('Cache-Control: no-store');
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'use POST']);
    exit;
}
// Only from pages of this same website.
$origin = $_SERVER['HTTP_ORIGIN'] ?? '';
if ($origin !== '' && parse_url($origin, PHP_URL_HOST) !== parse_url('http://' . ($_SERVER['HTTP_HOST'] ?? ''), PHP_URL_HOST)) {
    http_response_code(403);
    echo json_encode(['error' => 'other website']);
    exit;
}
if (is_dir('/var/lib/phonegame/documentation-called')) {
    echo json_encode(['status' => 'already_called']);
    exit;
}
if (@touch('/var/lib/phonegame-web/documentation.request') === false) {
    $err = error_get_last()['message'] ?? 'unknown error';
    error_log('phonegame: could not plan the call: ' . $err);
    http_response_code(500);
    echo json_encode(['error' => 'could not plan the call', 'detail' => $err . ' (run sudo bash install.sh again)']);
    exit;
}
echo json_encode(['status' => 'planned']);
