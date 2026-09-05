from rest_framework import viewsets

from .models import JournalEntry, Memory
from .serializers import JournalEntrySerializer, MemorySerializer


class JournalEntryViewSet(viewsets.ModelViewSet):
    serializer_class = JournalEntrySerializer
    search_fields = ("title", "body")

    def get_queryset(self):
        return JournalEntry.objects.filter(user=self.request.user)

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)


class MemoryViewSet(viewsets.ModelViewSet):
    serializer_class = MemorySerializer

    def get_queryset(self):
        return Memory.objects.filter(user=self.request.user)

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)
