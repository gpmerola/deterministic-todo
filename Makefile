.PHONY: check check-generated check-docs test-tools

check: test-tools check-docs
	flutter analyze
	flutter test

check-generated:
	dart run build_runner build
	git diff --exit-code -- lib/data/local/database.g.dart

check-docs:
	python3 tools/check_docs.py

test-tools:
	python3 -m unittest discover -s tools -p 'test_*.py'
