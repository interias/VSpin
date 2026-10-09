## GUT-Pre-Run-Hook (#62, TestIsolation): prüft `VSPIN_PORT_BASE`, hält das echte `user://` für den Vergleich in
## `post_run_check.gd` fest und legt den Gelände-Cache in das Testverzeichnis dieses Laufs.
extends GutHookScript


func run() -> void:
	var error := TestIsolation.port_base_error()
	if not error.is_empty():
		gut.logger.error(error)
		# GUT nimmt den Exit-Code nur vom Post-Run-Hook; nach `abort()` endet der Lauf sonst mit 0.
		gut.get_post_run_script_instance().set_exit_code(1)
		abort()
		return
	TestIsolation.remember_user_dir()
	IslandTerrain.cache_path = TestIsolation.path("terrain_cache.bin")
	print("Testisolation: %s=%d, Fake-Bus ab Port %d, Testdateien in %s" % [TestIsolation.PORT_BASE_ENV,
		TestIsolation.port_base(), TestIsolation.first_test_port(), TestIsolation.user_dir()])
