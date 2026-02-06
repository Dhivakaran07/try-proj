<?php
$server_ip = $_SERVER['SERVER_ADDR'] ?? 'unknown';
$hostname  = gethostname();
?>
<!DOCTYPE html>
<html>
<head>
  <title>Streamline Directory</title>
  <link rel="stylesheet" href="style.css">
</head>
<body class="v1">
  <div class="card">
    <h1>Welcome to Streamline - v1</h1>
    <p><b>Server IP:</b> <?php echo htmlspecialchars($server_ip); ?></p>
    <p><b>Hostname:</b> <?php echo htmlspecialchars($hostname); ?></p>
    <p>Load Balancer will distribute requests across instances.</p>
  </div>
</body>
</html>
