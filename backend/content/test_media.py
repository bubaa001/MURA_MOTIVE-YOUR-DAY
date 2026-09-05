from rest_framework.test import APITestCase

from accounts.models import User
from .models import ContentItem


class ContentMediaApiTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(username="content-reader", password="strong-pass-123")
        self.client.force_authenticate(self.user)

    def test_content_image_is_returned_as_media_url(self):
        item = ContentItem.objects.create(
            type="quote",
            text="A quote with artwork",
            image="content/2026/08/quote.png",
        )
        response = self.client.get(f"/api/v1/content/items/{item.pk}/")
        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(response.json()["image"], "http://testserver/media/content/2026/08/quote.png")

    def test_content_image_upload_requires_staff(self):
        item = ContentItem.objects.create(type="prayer", text="A prayer")
        response = self.client.post(
            f"/api/v1/content/items/{item.pk}/image/",
            {},
            format="multipart",
        )
        self.assertEqual(response.status_code, 403)
