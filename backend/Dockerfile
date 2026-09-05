# MURA backend — production image
FROM python:3.14-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .

RUN touch /app/db.sqlite3

RUN mkdir -p /app/media /app/staticfiles /app/data \
    && useradd --create-home --uid 1000 appuser \
    && chown -R appuser:appuser /app

USER appuser

# Collect static files into /app/staticfiles
RUN SECRET_KEY=dummy-build-key python manage.py collectstatic --noinput

ENV PORT=8000
EXPOSE 8000

CMD ["sh", "-c", "python manage.py migrate --noinput && python manage.py bootstrap_dev && exec gunicorn config.wsgi:application --bind 0.0.0.0:${PORT:-8000} --workers 3 --threads 2 --access-logfile - --error-logfile -"]