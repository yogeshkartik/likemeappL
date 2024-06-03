
// var lat = 0;
// var long = 0;


// function updateloc() {
//   const status = document.querySelector("#status");
//   const mapLink = document.querySelector("#map-link");


//   // JavaScript code


  
  
//   mapLink.href = "";
//   mapLink.textContent = "";

//   function success(position) {
//     const latitude = position.coords.latitude;
//     const longitude = position.coords.longitude;

//     status.textContent = "";
//     mapLink.href = `https://www.openstreetmap.org/#map=18/${latitude}/${longitude}`;
//     mapLink.textContent = `Latitude: ${latitude} °, Longitude: ${longitude} °`;



// //   //   $.ajax({
// //   //     url: 'http://127.0.0.1:8000/feed/',
// //   //     type: 'POST',
// //   //     data: {
// //   //         lat: latitude,
// //   //         long: longitude
// //   //     },
// //   //     success: function(response) {
// //   //         // Do something with the response
// //   //         document.location='http://127.0.0.1:8000/feed/'

// //   // });
    
    

// //     // const data = {
// //     //   lat: latitude,
// //     //   long: longitude,
// //     // };

// //     // fetch('#', {
// //     //   method: 'POST',
// //     //   headers: {
// //     //     'Content-Type': 'application/json',
// //     //   },
// //     //   body: JSON.stringify(data),
// //     // })
// //     //   .then(response => response.json())
// //     //   .then(data => console.log(data));



// //   }

//   function error() {
//     status.textContent = "Unable to retrieve your location";
//   }

//   if (!navigator.geolocation) {
//     status.textContent = "Geolocation is not supported by your browser";
//   } else {
//     status.textContent = "Locating…";
//     navigator.geolocation.getCurrentPosition(success, error);
//   }
// }

// document.querySelector("#find-me").addEventListener("click", updateloc);



// // $('#updatelocbtn').click(function(){
// //   // var catid;
// //   const latitude = position.coords.latitude;
// //   const longitude = position.coords.longitude;
// //   // catid = $(this).attr("data-catid");
// //    $.get('/feed/', {lat: latitude , lon: longitude});
// // });




function geoFindMe() {
  const status = document.querySelector("#status");
  


  function success(position) {
    const latitude = position.coords.latitude;
    const longitude = position.coords.longitude;

    status.textContent = "";
  
  }

  function error() {
    status.textContent = "Unable to retrieve your location";
  }

  if (!navigator.geolocation) {
    status.textContent = "Geolocation is not supported by your browser";
  } else {
    status.textContent = "Locating…";
    navigator.geolocation.getCurrentPosition(success, error);
  }
}

document.querySelector("#find-me").addEventListener("click", geoFindMe);