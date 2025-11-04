<?php
// Respeta el HTTPS cuando estamos detrás de un ALB que envía X-Forwarded-Proto
if (!empty($_SERVER['HTTP_X_FORWARDED_PROTO']) && strtolower($_SERVER['HTTP_X_FORWARDED_PROTO']) === 'https') {
    $_SERVER['HTTPS'] = 'on';
}

require "autoloader.php";
require "error_handler.php";
