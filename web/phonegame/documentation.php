<?php
// Phone Game: the website calls this when the player opens /documentation.
// It leaves a request file; the server (phonegame-web.path) then plans the call. The phone rings once,
// and only after the player has heard the clue call.
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
// Opened before the player has heard the clue on the phone (or before playing at all): do nothing,
// so the final call isn't used up and nothing on the page gives the story away.
if (!file_exists('/var/lib/phonegame/clue-heard')) {
    echo json_encode(['status' => 'too_early']);
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
