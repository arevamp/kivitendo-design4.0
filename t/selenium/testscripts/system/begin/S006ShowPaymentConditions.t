diag("Show payment conditions");

$sel->select_frame_ok("relative=up");
$sel->click_ok("link=Zahlungskonditionen anzeigen");
$sel->wait_for_page_to_load($lxtest->{timeout});
$sel->select_frame_ok("main_window");
$sel->click_ok("link=Schnellzahler/Skonto");
$sel->wait_for_page_to_load($lxtest->{timeout});
$sel->click_ok("action");
$sel->wait_for_page_to_load($lxtest->{timeout});