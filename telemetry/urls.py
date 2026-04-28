from django.urls import path

from . import views

urlpatterns = [
    path("", views.dashboard, name="dashboard"),
    path("vehicles/<str:vehicle_id>/", views.vehicle_detail, name="vehicle_detail"),
    path("admin-tools/", views.admin_tools, name="admin_tools"),
]
