    # path('/redirect/', usersview.redirect_view),
from django.urls import path
# from .views import createuser
# from feed import views as feedviews

from . import views

urlpatterns = [
    # path('/redirect/', createuser)
    # path('create-user/', createuser),
    # path('login-user/', loginuser),
    # path('feed/', include('feed.urls')),
    # path('feed/', feedviews.feed),
    # path('/home/')
    # ... more URL patterns here

    path('', views.register, name="user-register"),
    path('login/', views.userlogin, name="user-login")
]