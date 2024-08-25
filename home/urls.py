from django.urls import path

# from .views import homepage, feed
from . import views

urlpatterns = [
    # path("", homepage, name="home"),
    # path("feed/", feed, name="feed"),

    path("", views.homepage, name="home-homepage"),
    path("feed/<int:pk>/", views.feed, name="home-feed"),
    path("location/", views.location, name="home-location"),
    path("testurl/", views.testurl, name="home-testurl"),
    path("uploadfile/", views.upload_file, name="home-uploadfile"),
    path("createpost/", views.create_post, name="home-createpost"),
    path("post/<int:pk>/", views.post_detail, name="post_detail"),
    # path(r'^feed/$', views.feed, name="home-feed"),
    # url(r'^like_category/$', views.like_category, name='like_category'),
]
