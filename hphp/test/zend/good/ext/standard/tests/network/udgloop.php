<?hh <<__EntryPoint>> function main(): void {
$uniqid = uniqid();
if (file_exists("/tmp/$uniqid.sock"))
    die('Temporary socket /tmp/$uniqid.sock already exists.');

/* Setup socket server */
$errno = null;
$errstr = null;
$server = stream_socket_server("udg:///tmp/$uniqid.sock", inout $errno, inout $errstr, STREAM_SERVER_BIND);
if (!$server) {
    die('Unable to create AF_UNIX socket [server]');
}

/* Connect to it */
$client = stream_socket_client("udg:///tmp/$uniqid.sock", inout $errno, inout $errstr);
if (!$client) {
    die('Unable to create AF_UNIX socket [client]');
}

fwrite($client, "ABCdef123\n");

$data = fread($server, 10);
var_dump($data);

fclose($client);
fclose($server);
unlink("/tmp/$uniqid.sock");
}
