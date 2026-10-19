# Knowra — one place for the commands that need arguments you would otherwise
# have to remember. Every `run` target passes --dart-define-from-file, because
# a build without it silently has no OAuth client ids.

APP := app

.DEFAULT_GOAL := help

## ---------------------------------------------------------------- app ----

run: ## Run the app against the dev config (the usual one)
	cd $(APP) && flutter run --dart-define-from-file=config/dev.json

run-prod: ## Run a release build against the prod config
	cd $(APP) && flutter run --release --dart-define-from-file=config/prod.json

run-clean: ## Full rebuild — needed after any Info.plist or native change
	cd $(APP) && flutter clean && flutter pub get && \
	  flutter run --dart-define-from-file=config/dev.json

gen: ## Re-run code generation (freezed, json, injectable)
	cd $(APP) && dart run build_runner build

icons: ## Re-render the launcher icon from the orb widget, then cut sizes
	cd $(APP) && flutter test test/tools/generate_app_icons.dart && \
	  dart run flutter_launcher_icons && dart run flutter_native_splash:create

ios-url-scheme: ## Sync the Google sign-in URL scheme from GoogleService-Info.plist
	cd $(APP) && python3 tool/sync_ios_url_scheme.py

goldens: ## Regenerate every golden image
	cd $(APP) && flutter test --update-goldens

test-app: ## Analyze and test the Flutter app
	cd $(APP) && flutter analyze && flutter test

## ----------------------------------------------------------- firebase ----

FB   := firebase
FBPY := $(FB)/functions/venv/bin

emulate: ## Run the whole backend locally — no deploy, no Blaze needed
	cd $(FB) && firebase emulators:start

deploy: ## Push rules, indexes and functions
	cd $(FB) && firebase deploy --only firestore:rules,firestore:indexes,functions

deploy-rules: ## Push just the security rules
	cd $(FB) && firebase deploy --only firestore:rules

logs: ## Tail the Cloud Functions log — sign-in codes appear here
	cd $(FB) && firebase functions:log

test-api: ## Test the Cloud Functions
	cd $(FB)/functions && ./venv/bin/python -m pytest -q

## --------------------------------------------------------------- both ----

dev: ## Emulators plus the app
	@echo "Start emulators in another tab: make emulate"
	$(MAKE) run

test: test-api test-app ## Everything

help:
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

.PHONY: run run-prod run-clean gen icons ios-url-scheme goldens test-app emulate deploy \
        deploy-rules logs test-api dev test help
