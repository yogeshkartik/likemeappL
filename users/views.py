from django.shortcuts import render, redirect ,reverse
from django.http import HttpResponse, HttpResponseRedirect

from django.contrib.auth.models import User,auth
from django.contrib.auth import login, authenticate
from django.contrib import messages


def register(request):

    if request.method == 'POST':

        username1 = request.POST['username']

        email1 = request.POST['email']

        password = request.POST['password']

        passwordagain = request.POST['password-again']

        if password==passwordagain:

            if User.objects.filter(email = email1).exists():

                messages.info(request,'Email already exists')

                return redirect('user-register')

            elif User.objects.filter(username = username1).exists():

                messages.info(request,'Username not available')

                return redirect('user-register')

            else:

                user= User.objects.create_user(username=username1,email=email1,password=password)

                user.save()

                return redirect('/')

        else:

            messages.info(request,' Password not the same')

            return redirect('user-register')

    else:

        return render(request, 'createuserid.html')
    

def userlogin(request):

    if request.method == 'POST':

        username1 = request.POST['username']

        # email1 = request.POST['email']

        password1 = request.POST['password1']

        user = authenticate(username=username1, password=password1)
        # if user:  # If the returned object is not None
        if user is not None:
                login(request, user)  # we connect the user
                # return redirect('feed/')
                # messages.info(request,'you are loged in')
                return redirect('home-location')
                # return HttpResponseRedirect(reverse('feed/'))
         
        else:
               messages.info(request,'username or password entered are incorrect. Please enter again')
               return redirect('user-login')
            # return HttpResponse("hello user you are loged in")

    


    else:

        return render(request, 'login-user.html')