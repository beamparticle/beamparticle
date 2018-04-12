#!efene
#_ ""
#_ "api_simple_efene"
#_ ""
#_ "A sample efene code to return what was passed in as the first argument."
#_ "Notice that this template works for the /api/<thisfun> interface, where"
#_ "json input is passed in the first argument postBody, while the response"
#_ "is a binary or a string, which must be json as well."
#_ ""
#_ "Read about Efene at efene.org"
#_ "see http://efene.org/language-introduction.html"
#_ ""

fn
    case Body, Context:
          Body
end
