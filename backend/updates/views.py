from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response

from .models import Release


@api_view(["GET"])
@permission_classes([AllowAny])
def manifest(request):
    """GET /api/v1/update/ -> latest release manifest (no auth required).

    {version_code, version_name, notes, apk_url, released_at} or 404 when no
    release has been published yet.
    """
    release = Release.objects.order_by("-version_code").first()
    if release is None:
        return Response({"detail": "No release published yet."}, status=404)
    apk_url = release.apk_url_override or request.build_absolute_uri(release.apk.url)
    return Response(
        {
            "version_code": release.version_code,
            "version_name": release.version_name,
            "notes": release.notes,
            "apk_url": apk_url,
            "released_at": release.created_at,
        }
    )
