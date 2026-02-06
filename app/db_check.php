<?php
$host = getenv('DB_HOST');
$user = getenv('DB_USER');
$pass = getenv('DB_PASS');
$db   = getenv('DB_NAME');

header('Content-Type: text/plain');

if (!$host || !$user || !$pass || !$db) {
  echo "Missing DB env vars. Set DB_HOST, DB_USER, DB_PASS, DB_NAME.\n";
  exit(1);
}

$conn = new mysqli($host, $user, $pass, $db);

if ($conn->connect_error) {
  echo "DB Connection FAILED: " . $conn->connect_error . "\n";
  exit(1);
}

echo "Database Connected Successfully\n";
$conn->close();
