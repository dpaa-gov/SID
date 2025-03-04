shinyServer(function(input, output, session){
    source("./server/reference_s.r", local=TRUE) 
    source("./server/stature_estimation_s.r", local=TRUE) 
    source("./server/stature_association_s.r", local=TRUE) 
})