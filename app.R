# setup --------------------------------------------------------------------
library(shiny)
library(leaflet)
library(googleway)
library(googlesheets4)
library(data.table)
library(shinyCAPTCHA)
library(leaflet.extras)
library(shinyjs)

# define values for all the constants ------------------------------------
GOOGLE_MAPS_API_KEY <- 
RECAPTCHA_SITE_KEY <- 
RECAPTCHA_SECRET_KEY <-
GOOGLE_SHEETS_ID <- #get sheet id: as_sheets_id(URL)

DATA_READ_SHEET_NAME <- "MeanRatingTable" #sheet from which to read the data
DATA_WRITE_SHEET_NAME <- "Raw" #sheet to which we write the data to

# google maps api key ---------------------------------------------------------
set_key(key = GOOGLE_MAPS_API_KEY)
google_keys()

# non-interactive auth for googlesheets to read and write data ----------------
options(gargle_oauth_cache = ".secrets",
        email = "youremail@id") #for the first time, and then the command below
# gs4_auth(path = '.secrets/filename_of_service_acc_token.json')

# read existing data on googlesheet to plot on map ---------------------------
dtDatasofar <- as.data.table(read_sheet(ss = GOOGLE_SHEETS_ID,
                                        sheet = DATA_READ_SHEET_NAME))
if (nrow(dtDatasofar) > 0) {
  dtDatasofar[, Latitude := as.numeric(Lat)]
  dtDatasofar[, Longitude := as.numeric(Lng)]
  dtDatasofar <- dtDatasofar[!is.na(MeanRating)]
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
                 <script src='https://maps.googleapis.com/maps/api/js?key=", GOOGLE_MAPS_API_KEY, "&libraries=places&callback=initAutocomplete' async defer></script>")),
      sliderInput("sliderinput",
                  "Sustainability Rating:",
                  min = 1,
                  max = 5,
                  value = 2),
      recaptchaUI("test", 
                  sitekey = RECAPTCHA_SITE_KEY),
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
      sapply(dtData[, MeanRating], function(rating) {
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
        addResetMapButton() %>%
        addMarkers(~Longitude,
                   ~Latitude,
                   icon = ~ColoredIcons[MarkerColor],
                   group = "markers",
                   label = paste0(dtDatasofar[, EateryName],
                                  ":",
                                  dtDatasofar[, MeanRating]),
                   clusterId = "cluster",
                   clusterOptions = markerClusterOptions())  %>% 
        addSearchFeatures(targetGroups = "markers", 
                          options = searchFeaturesOptions())
      #Additional map options: clusters, search button, home button
    } else {
      #empty map when no data
      map <- leaflet() %>% addTiles()
    }
  }
  )
  #recaptcha 
  result <- callModule(recaptcha,
                       "test",
                       secret = RECAPTCHA_SECRET_KEY)
  
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
    sheet_append(ss = GOOGLE_SHEETS_ID,
                 data = dtData,
                 sheet = DATA_WRITE_SHEET_NAME)
    
    #Say thankyou
    h5("Thanks for entering data. View all responses",
       a("here",
         href = paste0("https://docs.google.com/spreadsheets/d/",GOOGLE_SHEETS_ID,"/edit?usp=sharing")
         )
    )
  })
}

# Run the application
shinyApp(ui = ui, server = server)

