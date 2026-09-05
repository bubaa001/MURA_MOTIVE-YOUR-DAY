"""Auth endpoints, mounted by config.urls at /api/v1/auth/."""
from django.urls import path
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView

from .serializers import EmailOrUsernameTokenObtainPairSerializer
from .views import EmployeeRegisterView, RegisterView


class EmailOrUsernameTokenObtainPairView(TokenObtainPairView):
    serializer_class = EmailOrUsernameTokenObtainPairSerializer

urlpatterns = [
    path("token/", EmailOrUsernameTokenObtainPairView.as_view(), name="token_obtain_pair"),
    path("token/refresh/", TokenRefreshView.as_view(), name="token_refresh"),
    path("register/", RegisterView.as_view(), name="register"),
    path("register/employee/", EmployeeRegisterView.as_view(), name="employee_register"),
]
