from rest_framework import generics, permissions, status
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response
from rest_framework_simplejwt.tokens import RefreshToken

from .models import User
from .serializers import EmployeeRegisterSerializer, RegisterSerializer, UserSerializer


class RegisterView(generics.CreateAPIView):
    """POST /api/v1/auth/register/ -> creates the account -> {access, refresh}."""

    queryset = User.objects.all()
    serializer_class = RegisterSerializer
    permission_classes = (permissions.AllowAny,)

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        # Contract: registration returns the same token pair as /auth/token/.
        refresh = RefreshToken.for_user(user)
        return Response(
            {"access": str(refresh.access_token), "refresh": str(refresh)},
            status=status.HTTP_201_CREATED,
        )


class EmployeeRegisterView(RegisterView):
    """POST /auth/register/employee/ -> creates a Feeder staff account."""

    serializer_class = EmployeeRegisterSerializer


class MeView(generics.RetrieveUpdateAPIView):
    """GET/PATCH /api/v1/me/ — the signed-in user's profile."""

    serializer_class = UserSerializer
    parser_classes = (JSONParser, MultiPartParser, FormParser)

    def get_object(self):
        return self.request.user


class AvatarView(generics.GenericAPIView):
    """POST/DELETE /api/v1/me/avatar/ for the signed-in user's avatar."""

    serializer_class = UserSerializer
    permission_classes = (permissions.IsAuthenticated,)
    parser_classes = (MultiPartParser, FormParser)

    def post(self, request, *args, **kwargs):
        upload = request.FILES.get("avatar")
        if upload is None:
            return Response(
                {"avatar": ["This file is required."]},
                status=status.HTTP_400_BAD_REQUEST,
            )
        serializer = self.get_serializer(
            request.user,
            data={"avatar": upload},
            partial=True,
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)

    def delete(self, request, *args, **kwargs):
        user = request.user
        if user.avatar:
            user.avatar.delete(save=False)
            user.avatar = None
            user.save(update_fields=("avatar",))
        return Response(self.get_serializer(user).data)
