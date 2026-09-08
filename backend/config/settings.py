"""
Django settings for the MURA backend.

Dev-first defaults: SQLite works out of the box, PostgreSQL is enabled by
setting DB_* variables (see .env.example). Everything reads environment
variables so the same settings file serves local dev and production hosts.
"""
from __future__ import annotations

import os
import sys
from datetime import timedelta
from pathlib import Path

from .env import load_env

BASE_DIR = Path(__file__).resolve().parent.parent
load_env(BASE_DIR)


def env(key: str, default: str = "") -> str:
    return os.environ.get(key, default)


def env_bool(key: str, default: bool = False) -> bool:
    return env(key, str(default)).strip().lower() in {"1", "true", "yes", "on"}


# The whole suite runs from one client/user, so it would trip the per-minute
# buckets long before it finished; throttle rates are meaningless in tests.
_in_test_run = "test" in sys.argv


# --- Core ---
SECRET_KEY = env("SECRET_KEY", "dev-only-insecure-key-change-me")
DEBUG = env_bool("DEBUG", False)
if not DEBUG and SECRET_KEY == "dev-only-insecure-key-change-me":
    # Fail-closed: a production host must never sign JWTs with the public dev key.
    from django.core.exceptions import ImproperlyConfigured

    raise ImproperlyConfigured("SECRET_KEY must be set to a real secret in production.")
_configured_hosts = [
    h.strip()
    for h in env(
        "ALLOWED_HOSTS",
        # Default keeps local dev working and the PythonAnywhere deployment
        # reachable even when ALLOWED_HOSTS is not set in its .env.
        "127.0.0.1,localhost,testserver,bubaa.pythonanywhere.com",
    ).split(",")
    if h.strip()
]
_ngrok_hosts = [
    h.strip()
    for h in env(
        "NGROK_ALLOWED_HOSTS",
        ".ngrok-free.app,.ngrok-free.dev,.ngrok.io,.ngrok.app",
    ).split(",")
    if h.strip()
]
ALLOWED_HOSTS = list(dict.fromkeys(_configured_hosts + _ngrok_hosts))
if DEBUG:
    import logging

    logging.getLogger(__name__).warning(
        "DEBUG=True on host list %r — stack traces and settings will be exposed "
        "to anyone who triggers an error. Set DEBUG=false in this environment's .env.",
        ALLOWED_HOSTS,
    )

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    # Third party
    "rest_framework",
    "corsheaders",
    # MURA apps
    "accounts.apps.AccountsConfig",
    "habits.apps.HabitsConfig",
    "content.apps.ContentConfig",
    "wealth.apps.WealthConfig",
    "goals.apps.GoalsConfig",
    "journal.apps.JournalConfig",
    "priorities.apps.PrioritiesConfig",
    "reminders.apps.RemindersConfig",
    "feeder",
    "automations",
    "updates.apps.UpdatesConfig",
]

MIDDLEWARE = [
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",  # Must follow SecurityMiddleware
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

WSGI_APPLICATION = "config.wsgi.application"

# --- Database ---
if env("DB_ENGINE") == "postgresql":
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.postgresql",
            "NAME": env("DB_NAME", "mura"),
            "USER": env("DB_USER", "postgres"),
            "PASSWORD": env("DB_PASSWORD", ""),
            "HOST": env("DB_HOST", "127.0.0.1"),
            "PORT": env("DB_PORT", "5432"),
        }
    }
else:
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": BASE_DIR / "db.sqlite3",
            "OPTIONS": {"timeout": 30},
        }
    }

# --- Auth ---
AUTH_USER_MODEL = "accounts.User"
AUTH_PASSWORD_VALIDATORS = [
    {
        "NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"
    },
    {
        "NAME": "django.contrib.auth.password_validation.MinimumLengthValidator",
        "OPTIONS": {"min_length": 8},
    },
    {
        "NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"
    },
    {
        "NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"
    },
]

# --- REST framework / JWT ---
REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": (
        "rest_framework_simplejwt.authentication.JWTAuthentication",
    ),
    "DEFAULT_PERMISSION_CLASSES": (
        "rest_framework.permissions.IsAuthenticated",
    ),
    "DEFAULT_PAGINATION_CLASS": "config.pagination.DefaultPagination",
    "DEFAULT_FILTER_BACKENDS": (
        "rest_framework.filters.SearchFilter",
        "rest_framework.filters.OrderingFilter",
    ),
    # AnonRate throttles brute-force login attempts; user rate is a safety net
    # against a single client hammering the one shared PythonAnywhere worker.
    # The mobile app bursts ~15 requests per tab switch / app resume (every
    # mounted page refetches), so 120/min throttled NORMAL use and broke
    # automations, journal reloads and push-device registration. 600/min =
    # 10/s still protects the worker but never trips a real user.
    "DEFAULT_THROTTLE_CLASSES": (
        ()
        if _in_test_run
        else (
            "rest_framework.throttling.AnonRateThrottle",
            "rest_framework.throttling.UserRateThrottle",
        )
    ),
    "DEFAULT_THROTTLE_RATES": {
        "anon": "30/min",
        "user": "600/min",
    },
}

# PythonAnywhere terminates HTTPS at its proxy and forwards plain HTTP to
# Django; without this header request.build_absolute_uri() (avatars, content
# artwork, memories) emits http:// URLs that Android blocks on release builds.
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(days=1),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=30),
    "ROTATE_REFRESH_TOKENS": True,
}

# --- CORS ---
CORS_ALLOW_ALL_ORIGINS = env_bool("CORS_ALLOW_ALL", True)
if not CORS_ALLOW_ALL_ORIGINS:
    CORS_ALLOWED_ORIGINS = [
        origin.strip()
        for origin in env("CORS_ALLOWED_ORIGINS").split(",")
        if origin.strip()
    ]

# ngrok terminates TLS and forwards the original scheme in this header.
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
USE_X_FORWARDED_HOST = True
SECURE_SSL_REDIRECT = env_bool("SECURE_SSL_REDIRECT", False)
SECURE_COOKIES = env_bool("SECURE_COOKIES", not DEBUG)
SESSION_COOKIE_SECURE = SECURE_COOKIES
CSRF_COOKIE_SECURE = SECURE_COOKIES
CSRF_TRUSTED_ORIGINS = [
    origin.strip()
    for origin in env(
        "CSRF_TRUSTED_ORIGINS",
        "https://*.ngrok-free.app,https://*.ngrok-free.dev,https://*.ngrok.io,https://*.ngrok.app",
    ).split(",")
    if origin.strip()
]

# --- Google (FCM) push ---
SIGNO_NAMESPACE = env("SIGNO_NAMESPACE", "")
# Per-user topic namespace pattern: "{base}:{user_id}" keeps each account's
# pushes private (fixes the shared-namespace cross-user leak). The base
# namespace stays usable for owner broadcasts from the studio.
SIGNO_USER_NAMESPACE_TEMPLATE = env("SIGNO_USER_NAMESPACE_TEMPLATE", "{namespace}:{user_id}")

# --- FCM push (Firebase Cloud Messaging, HTTP v1) ---
# Primary push channel: reaches every Android phone without requiring any
# third-party app. Values come from a Firebase service-account key JSON
# (Project Settings -> Service accounts -> Generate new private key).
# Unset = push disabled; notify_user() delivers nothing (feed still logged).
FCM_PROJECT_ID = env("FCM_PROJECT_ID", "")
FCM_CLIENT_EMAIL = env("FCM_CLIENT_EMAIL", "")
# The PEM key with literal \n escapes as it appears in the downloaded JSON.
FCM_PRIVATE_KEY = env("FCM_PRIVATE_KEY", "")

# --- i18n / tz ---
LANGUAGE_CODE = "en-us"
TIME_ZONE = env("TIMEZONE", "UTC")
USE_I18N = True
USE_TZ = True

# --- Static / media ---
STATIC_URL = "/static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
MEDIA_URL = "/media/"
MEDIA_ROOT = BASE_DIR / "media"

STORAGES = {
    "default": {
        "BACKEND": "django.core.files.storage.FileSystemStorage",
    },
    "staticfiles": {
        "BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage",
    },
}

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

# --- TheFeeder (human review pipeline) ---
# Book upload / AI extraction was removed in 2026-08; candidates are written
# and reviewed by people. bulk-import stays disabled until SERVICE_API_KEY is set.
SERVICE_API_KEY = env("SERVICE_API_KEY")
# Required shared secret for /auth/register/employee/. Unset = employee
# registration is fully disabled (fail closed).
EMPLOYEE_SIGNUP_KEY = env("EMPLOYEE_SIGNUP_KEY")