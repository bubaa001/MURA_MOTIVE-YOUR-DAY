from django.contrib.auth.password_validation import validate_password
from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer

from .models import User


class UserSerializer(serializers.ModelSerializer):
    avatar = serializers.ImageField(required=False, allow_null=True)

    class Meta:
        model = User
        fields = (
            "id", "username", "email", "first_name", "display_name", "avatar",
            "date_joined", "is_staff", "is_superuser", "plan", "push_topic",
        )
        extra_kwargs = {
            "is_staff": {"read_only": True},
            "is_superuser": {"read_only": True},
            # plan/push_topic are server-controlled; a billing webhook flips plan.
            "plan": {"read_only": True},
            "push_topic": {"read_only": True},
        }
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
    signup_key = serializers.CharField(write_only=True, required=False, allow_blank=True)

    class Meta(RegisterSerializer.Meta):
        fields = ("username", "email", "password", "signup_key")

    def validate(self, attrs):
        from django.conf import settings
        import hmac

        expected = getattr(settings, "EMPLOYEE_SIGNUP_KEY", "")
        provided = attrs.pop("signup_key", "") or ""
        if not expected:
            raise serializers.ValidationError(
                {"signup_key": "Employee registration is disabled. Ask the owner to create staff accounts."}
            )
        if not hmac.compare_digest(expected, provided):
            raise serializers.ValidationError({"signup_key": "Invalid signup key."})
        return attrs

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
        if identifier and "@" in identifier:
            # Prefer an exact-username match first so two accounts that share
            # an email remain distinguishable at login.
            if not User.objects.filter(username=identifier).exists():
                matches = User.objects.filter(email__iexact=identifier).order_by("-is_active", "id")
                user = matches.first()
                if user is not None:
                    attrs[self.username_field] = user.get_username()
        return super().validate(attrs)
