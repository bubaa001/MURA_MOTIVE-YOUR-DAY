from rest_framework.pagination import PageNumberPagination


class DefaultPagination(PageNumberPagination):
    """Contract promises ?page= and ?page_size= — wire both."""

    page_size = 50
    page_size_query_param = "page_size"
    max_page_size = 200
