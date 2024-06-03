from django.shortcuts import render

from django.shortcuts import render, redirect
from django.http import HttpResponse, HttpResponseRedirect

from django.contrib.auth.models import User,auth
from django.contrib.auth import login, authenticate
from django.contrib import messages
import sqlite3


# def feed(request):
#     return HttpResponse("Hello world")

# def feed(request):

#     if request.method == 'POST':

#         lat = request.POST['latitude']

#         long = request.POST['longitude']

#         if request.user.is_authenticated:
#             # updateSqliteTable()
#             messages.info(request,'Your location updated!')
#             return redirect('/feed/')
#         else:
            
#             return redirect('/feed/')

    


#     else:

#         return render(request, 'login-user.html')





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





# def feed(request):

#     if request.user.is_authenticated:
#         if request.method == 'POST':

#             lat = request.POST['latitude']

#             long = request.POST['longitude']

#             # updateSqliteTable()
#             messages.info(request,'Your location updated!')
#             return redirect('/')
#         else:
            
#             return render(request, "feed.html")

    


#     else:
#         return redirect('user-login')

#         # return render(request, 'login-user.html')





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



