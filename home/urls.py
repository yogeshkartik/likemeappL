from django.urls import path

# from .views import homepage, feed
from . import views

urlpatterns = [
    # path("", homepage, name="home"),
    # path("feed/", feed, name="feed"),

    path("", views.homepage, name="home-homepage"),
    path("feed/", views.feed, name="home-feed"),
    path("location/", views.location, name="home-location"),
    path("testurl/", views.testurl, name="home-testurl"),
    # path(r'^feed/$', views.feed, name="home-feed"),
    # url(r'^like_category/$', views.like_category, name='like_category'),
]
