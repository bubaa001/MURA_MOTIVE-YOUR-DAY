from django.conf import settings
from rest_framework import permissions


class ServiceKeyPermission(permissions.BasePermission):
    """App-to-app auth: fixed secret in the X-Service-Key header.

    Checked against SERVICE_API_KEY from the environment. When the key is not
    configured the endpoint is effectively disabled (all requests denied) so it
    can never be accidentally left open.
    """

    def has_permission(self, request, view) -> bool:
        expected = getattr(settings, "SERVICE_API_KEY", "")
        if not expected:
            return False
        provided = request.headers.get("X-Service-Key", "")
        # constant-time compare
        import hmac

        return hmac.compare_digest(provided.encode(), expected.encode())
