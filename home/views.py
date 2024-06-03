from django.shortcuts import render

from django.shortcuts import render, redirect
from django.http import HttpResponse, HttpResponseRedirect

from django.contrib.auth.models import User,auth
from django.contrib.auth import login, authenticate
from django.contrib import messages
import sqlite3

from .models import Client
from django.contrib.gis.geos import Point




from django.contrib.gis.measure import Distance
import json
from django.http import JsonResponse


app_name = "home"
# Create your views here.
def homepage(request):

        
    # print("user authenticated222")
    # if request.method == 'POST':
        # if request.user.is_authenticated:
        # print("user authenticatedwwwwwwwwwwwww")
        # if User.is_authenticated:
        #     HttpResponse("Hello user you are authenticated")
        # else:
        #     return render(request, 'home.html')
        
    return render(request, 'home.html')

# def feed(request):
#     if request.user.is_authenticated:
#         return HttpResponse("Hello user you are authenticated recheck")
#         #     HttpResponse("Hello user you are authenticated")
#         # else:
#         #     return render(request, 'home.html')
    

def location(request):
    if request.user.is_authenticated:
        return render(request, "feed.html")
    else:
        return redirect('user-login')



def feed(request):

    if request.user.is_authenticated:
        # lat = float(request.GET.get('lat'))
        # lon = float(request.GET.get('lon'))
        # print(lat)
        # print(lon)


        
        # context = RequestContext(request)
        # lat = None
        # long = None
        if request.method == 'POST':
            data = json.loads(request.body)
            # lat = request.POST.get('latitude')
            # long = request.POST.get('longitude')
            lat = data['latitude']
            long = data['longitude']
    

        
        # if request.method == 'POST':
            # print(request)
            # lat = request.POST[""]

            # lat  = request.POST.get("latitude")
            # long  = request.POST.get("longitude")
            # lat  = request.POST["latitude"]
           

            # long = request.POST["longitude"]
            # print(lat)
            # print(long)
            pnt = Point(lat,long)
            # p = "POINT(-0.2153 45.6402)"
            current_user = request.user
            try:
                (Client.objects.get(username = current_user))
                update_loc = Client.objects.get(username = current_user)
                update_loc.location = pnt
                update_loc.save()
            except:
                user_instance = Client.objects.create(username=current_user.username, location=pnt)
                user_instance.save()

            # updateSqliteTable()
            # messages.info(request,'Your location updated!')


            url = '/testurl/'
        #if the above way doesn't work then try: url = request.build_absolute_uri(reverse('formulario' , kwargs = {'_id' : _id}))
        #Now simply return a JsonResponse. Ideally while dealing with ajax, Json is preferred. 
            return JsonResponse(status = 302 , data = {'success' : url })
            
            # return redirect('/')
            # return HttpResponse('/')
        else:
            
            return render(request, "feed.html")

    


    else:
        return redirect('user-login')

        # return render(request, 'login-user.html')



def testurl(request):
    # p = Point(455,44)
    # p = "POINT(-0.2153 45.6402)"

    # user_instance = Client.objects.create(username='testuser', location=p)
    # user_instance.save()



    # clients_within_radius = Client.objects.filter(
    #     location__distance_lt=(
    #         Point(-0.2153 45.6402),
    #         Distance(m=5000)
    #     )
    # )




    # distance = 2000 
    # ref_location = Point(1.232433, 1.2323232)

    # res = Client.objects.filter(
    #     location__distance_lte=(
    #         ref_location,
    #         Distance(m=distance)
    #     )
    # ).order_by(
    #     'location'
    # )



    # center = Point(-0.2153, 45.6402)  # The center of the circle

    current_user = request.user
    # id=current_user.id
    # print(id)
    current_user_loc = Client.objects.get(username = current_user).location
    # c_u_location = current_user_loc.location
    # print(c_u_location)
    print(current_user_loc)
    print(type(current_user_loc))
    y = current_user_loc.coords
    print(current_user_loc.coords)

    loc_list = list(y)
    print(loc_list)
    print(type(loc_list))
    # z = current_user_loc.json
    # print(type(z))
    
    
    center = Point(loc_list[0], loc_list[1])  # The center of the circle
    radius = Distance(km=5.9)  # The radius of the circle

    # Retrieve all clients within the circle
    clients = Client.objects.filter(location__distance_lte=(center, radius)).order_by('id').values()
    # cust_data = Client.objects.get(id=34)
    # name = Client.objects.get(id)

    # x = Client.objects.all()[5]
    # x.location = Point(64, 88)

    # x.save()

    # print(res)
    q = Client.objects.all().values()
    # print(q)
    # return HttpResponse(clients)
    return render(request, "testurl.html", {'users':clients})



# def updateSqliteTable():
#     try:
#         sqliteConnection = sqlite3.connect('SQLite_Python.db')
#         cursor = sqliteConnection.cursor()
#         print("Connected to SQLite")

#         sql_update_query = """Update SqliteDb_developers set salary = 10000 where id = 4"""
#         cursor.execute(sql_update_query)
#         sqliteConnection.commit()
#         print("Record Updated successfully ")
#         cursor.close()

#     except sqlite3.Error as error:
#         print("Failed to update sqlite table", error)
#     finally:
#         if sqliteConnection:
#             sqliteConnection.close()
#             print("The SQLite connection is closed")



