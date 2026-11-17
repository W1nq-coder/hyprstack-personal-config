.PHONY: check run smoke
check:
	python3 -m compileall -q src scripts
	PYTHONPATH=src python3 -m unittest discover -s tests -v
	@for script in scripts/*.sh; do sh -n "$$script" || exit; done
run:
	./scripts/run.sh
smoke:
	./scripts/run.sh --smoke-test
