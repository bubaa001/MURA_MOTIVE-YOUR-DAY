from django.contrib.auth.password_validation import validate_password
from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer

from .models import User


class UserSerializer(serializers.ModelSerializer):
    avatar = serializers.ImageField(required=False, allow_null=True)

    class Meta:
        model = User
        fields = ("id", "username", "email", "first_name", "display_name", "avatar", "date_joined", "is_staff", "is_superuser")
        extra_kwargs = {"is_staff": {"read_only": True}, "is_superuser": {"read_only": True}}
        read_only_fields = ("id", "username", "date_joined")

    def update(self, instance, validated_data):
        old_avatar = instance.avatar.name if instance.avatar else None
        updated = super().update(instance, validated_data)
        new_avatar = updated.avatar.name if updated.avatar else None
        if old_avatar and old_avatar != new_avatar:
            instance.avatar.storage.delete(old_avatar)
        return updated


class RegisterSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, trim_whitespace=False)

    class Meta:
        model = User
        fields = ("username", "email", "password")

    def validate_password(self, value: str) -> str:
        validate_password(value)
        return value

    def create(self, validated_data):
        return User.objects.create_user(
            username=validated_data["username"],
            email=validated_data.get("email", ""),
            password=validated_data["password"],
        )


class EmployeeRegisterSerializer(RegisterSerializer):
    def create(self, validated_data):
        return User.objects.create_user(
            username=validated_data["username"],
            email=validated_data.get("email", ""),
            password=validated_data["password"],
            is_staff=True,
            is_superuser=False,
        )


class EmailOrUsernameTokenObtainPairSerializer(TokenObtainPairSerializer):
    """Allow the mobile client to sign in with either identifier."""

    def validate(self, attrs):
        identifier = attrs.get(self.username_field)
        if identifier:
            user = User.objects.filter(email__iexact=identifier).first()
            if user is not None:
                attrs[self.username_field] = user.get_username()
        return super().validate(attrs)
