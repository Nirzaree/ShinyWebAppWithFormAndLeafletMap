# setup --------------------------------------------------------------------
library(shiny)
library(leaflet)
library(googleway)
library(googlesheets4)
library(data.table)
library(inlmisc)
library(shinyCAPTCHA)
library(shinyjs)

# google maps api key ---------------------------------------------------------
key <- "yourKey"
set_key(key = key)
google_keys()

# non-interactive auth for googlesheets to read and write data ----------------
options(gargle_oauth_cache = ".secrets",
        email = "youremail@id")

# gs4_auth() #required once for the project

#get sheet id: as_sheets_id(URL)
sheet_id <- "yoursheet_id"

# read existing data on googlesheet to plot on map ---------------------------
dtDatasofar <- as.data.table(read_sheet(ss = sheet_id,
                                        sheet = "Aggregate"))
if (nrow(dtDatasofar) > 0) {
  dtDatasofar[, Latitude := as.numeric(Latitude)]
  dtDatasofar[, Longitude := as.numeric(Longitude)]
  names(dtDatasofar)[names(dtDatasofar) == "AVERAGE of Rating"] <- "meanRating"
  dtDatasofar <- dtDatasofar[!is.na(meanRating)]
}

# ui logic -------------------------------------------------------------------------
ui <- fluidPage(
  # Application title
  h1("App with recaptcha",
     align = "center"),
  
  # Form on the sidebarpanel
  sidebarLayout(
    sidebarPanel(
      h4("Let's add some new data"),
      textInput("someaddress",
                "Enter some eatery address"),
      HTML(paste0(" <script> 
                function initAutocomplete() {
                 var autocomplete =   new google.maps.places.Autocomplete(document.getElementById('someaddress'));
                 autocomplete.addListener('place_changed', function() {
                 var place = autocomplete.getPlace();
                 Shiny.setInputValue('jsName', place.name);
                 Shiny.setInputValue('jsAddress', place.formatted_address);     
                 });
                 } </script> 
                 <script src='https://maps.googleapis.com/maps/api/js?key=", key, "&libraries=places&callback=initAutocomplete' async defer></script>")),
      sliderInput("sliderinput",
                  "Sustainability Rating:",
                  min = 1,
                  max = 5,
                  value = 2),
      recaptchaUI("test", 
                  sitekey = "yoursitekey"),
      uiOutput("humansOnly")
    ),
    # Plot existing data
    mainPanel(
      leafletOutput("LeafletMap"),
      uiOutput("thankyoutext")
    )
  )
)

# Server logic
server <- function(input, output) {
  #Leaflet render logic
  output$LeafletMap <- renderLeaflet({
    #function to get color of the marker based on the mean rating 
    getColor <- function(dtData) {
      sapply(dtData[, meanRating], function(rating) {
        if (rating >= 4) {
          "green"
        } else if (rating >= 3) {
          "orange"
        } else {
          "red"
        }
      })
    }
    
    ColoredIcons <- iconList(green = makeIcon("marker-icon-green.png",
                                              iconWidth = 24,
                                              iconHeight = 32),
                             orange = makeIcon("marker-icon-orange.png",
                                               iconWidth = 24,
                                               iconHeight = 32),
                             red = makeIcon("marker-icon-red.png",
                                            iconWidth = 24,
                                            iconHeight = 32)
    )
    
    if (nrow(dtDatasofar) > 0) {
      dtDatasofar[, "MarkerColor"] <- getColor(dtDatasofar)
      # Generate leaflet
      map <- leaflet(dtDatasofar) %>% 
        addTiles() %>% 
        addMarkers(~Longitude,
                   ~Latitude,
                   icon = ~ColoredIcons[MarkerColor],
                   group = "markers",
                   label = paste0(dtDatasofar[, Name],
                                  ":",
                                  dtDatasofar[, meanRating]),
                   clusterId = "cluster",
                   clusterOptions = markerClusterOptions())
      #Additional map options: clusters, search button, home button
      map <- inlmisc::AddHomeButton(map)
      map <- inlmisc::AddClusterButton(map,
                                       clusterId = "cluster")
      map <- inlmisc::AddSearchButton(map,
                                      group = "markers",
                                      zoom = 15,
                                      textPlaceholder = "Search here")
    } else {
      #empty map when no data
      map <- leaflet() %>% addTiles()
    }
  }
  )
  #recaptcha 
  result <- callModule(recaptcha,
                       "test",
                       secret = "yoursecretkey")
  
  #if recaptcha successful
  output$humansOnly <- renderUI({
    req(result()$success)
    #Collect data
    coords <- google_geocode(input$jsAddress)
    coords <- geocode_coordinates(coords)
    dtData <- data.table(
      timestamp <- Sys.time(),
      Name <- input$jsName,
      Address <- input$jsAddress,
      Latitude <- coords$lat[1],
      Longitude <- coords$lng[1],
      Rating <- input$sliderinput
    )
    #Put data on drive
    sheet_append(ss = sheet_id,
                 data = dtData,
                 sheet = "Raw")
    
    #Say thankyou
    h5("Thanks for entering data. View all responses",
       a("here",
         href = "https://docs.google.com/spreadsheets/d/yoursheet_id/edit?usp=sharing")
    )
  })
}

# Run the application
shinyApp(ui = ui, server = server)

