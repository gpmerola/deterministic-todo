.PHONY: check check-generated check-docs test-tools todo-test todo-test-adb todo-test-remote todo-test-ci

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

# Fastest safe delivery: ADB when connected, otherwise publish the locally built APK.
todo-test:
	python3 tools/todo_test_fast.py

todo-test-adb:
	python3 tools/todo_test_fast.py --mode adb

todo-test-remote:
	python3 tools/todo_test_fast.py --mode remote

todo-test-ci:
	gh workflow run publish-todo-test-fast.yml --ref $$(git branch --show-current)
