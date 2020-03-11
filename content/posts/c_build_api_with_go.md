---
title: "Build and Deploy a secure REST API with Go, Postgresql, JWT and GORM"
date: 2018-05-04 00:00:00 +0000
draft: false
---

In this tutorial, we are going to learn how to develop and deploy a secure REST api using Go Programming language.

## Why Go?

Go is a very interesting programming language, it is a strongly typed language which compiles very fast, it performance is likened to that of C++, go has goroutines — a much more efficient replacement for Threads, and also go give you the freedom to static type on the web — I understand this is not new, i just love Go’s way.

## What are we building?

We are going to build a **contact/phonebook manager App, **our API will allow users to add contacts to their profiles, they will be able to retrieve it in case their phone got lost.

## Prerequisites

This lesson assumed you already installed the following packages

* Go

* Postgresql

* GoLand IDE — optional(I am going to be using it for this tutorial)

I also assumed you have setup your GOPATH. Check this if you haven’t [https://github.com/golang/go/wiki/SettingGOPATH](https://github.com/golang/go/wiki/SettingGOPATH)

Let’s do it!

## What is REST?

REST stands for Representational State Transfer, it is the mechanism used by modern client apps to communicate with databases and servers via http — [https://en.wikipedia.org/wiki/Representational_state_transfer](https://en.wikipedia.org/wiki/Representational_state_transfer)
So, you have a new startup idea or you want to build that awesome side project? REST protocol is mostly the way to go.

## Building the App

We start by identifying the package dependencies we are going to need for this project, luckily for us, Go standard library is rich enough to build a complete website without using a third party framework(i hope i am right) — see net.http package, but to make our work easier, we are going to need the following packages,

* gorilla/mux — A powerful URL router and dispatcher. We use this package to match URL paths with their handlers.

* jinzhu/gorm — The fantastic ORM library for Golang, aims to be developer friendly. We use this ORM(Object relational mapper) package to interact smoothly with our database

* dgrijalva/jwt-go — Used to sign and verify JWT tokens

* joho/godotenv — Used to load .env files into the project

To install any of this package, open terminal and run

go get github.com/{package-name}

This command will install the packages into your GOPATH.

### Project Structure

![Check the left sidebar to see project structure](https://cdn-images-1.medium.com/max/2732/1*3MJjEDEI7i29eJecxxfopA.png)*Check the left sidebar to see project structure*

utils.go

```go
package utils

import (
	"encoding/json"
	"net/http"
)

func Message(status bool, message string) (map[string]interface{}) {
	return map[string]interface{} {"status" : status, "message" : message}
}

func Respond(w http.ResponseWriter, data map[string] interface{})  {
	w.Header().Add("Content-Type", "application/json")
	json.NewEncoder(w).Encode(data)
}
```

utils.go contain handy utils functions to build json messages and return a json response. Note the two function Message() and Respond() before we proceed.

### More about JWT

JSON Web Tokens are an open, industry standard [RFC 7519](https://tools.ietf.org/html/rfc7519) method for representing claims securely between two parties. It is easy to identify web application users through sessions, however, when your web apps API is interacting with say an Android or IOS client, sessions becomes unusable because of the stateless nature of the http request. With JWT, we can create a unique token for each authenticated user, this token would be included in the header of the subsequent request made to the API server, this method allow us to identify every users that make calls to our API. Lets see the implementation below

```go
package app

import (
	"net/http"
	u "lens/utils"
	"strings"
	"go-contacts/models"
	jwt "github.com/dgrijalva/jwt-go"
	"os"
	"context"
	"fmt"
)

var JwtAuthentication = func(next http.Handler) http.Handler {

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {

		notAuth := []string{"/api/user/new", "/api/user/login"} //List of endpoints that doesn't require auth
		requestPath := r.URL.Path //current request path

		//check if request does not need authentication, serve the request if it doesn't need it
		for _, value := range notAuth {

			if value == requestPath {
				next.ServeHTTP(w, r)
				return
			}
		}

		response := make(map[string] interface{})
		tokenHeader := r.Header.Get("Authorization") //Grab the token from the header

		if tokenHeader == "" { //Token is missing, returns with error code 403 Unauthorized
			response = u.Message(false, "Missing auth token")
			w.WriteHeader(http.StatusForbidden)
			w.Header().Add("Content-Type", "application/json")
			u.Respond(w, response)
			return
		}

		splitted := strings.Split(tokenHeader, " ") //The token normally comes in format `Bearer {token-body}`, we check if the retrieved token matched this requirement
		if len(splitted) != 2 {
			response = u.Message(false, "Invalid/Malformed auth token")
			w.WriteHeader(http.StatusForbidden)
			w.Header().Add("Content-Type", "application/json")
			u.Respond(w, response)
			return
		}

		tokenPart := splitted[1] //Grab the token part, what we are truly interested in
		tk := &models.Token{}

		token, err := jwt.ParseWithClaims(tokenPart, tk, func(token *jwt.Token) (interface{}, error) {
			return []byte(os.Getenv("token_password")), nil
		})

		if err != nil { //Malformed token, returns with http code 403 as usual
			response = u.Message(false, "Malformed authentication token")
			w.WriteHeader(http.StatusForbidden)
			w.Header().Add("Content-Type", "application/json")
			u.Respond(w, response)
			return
		}

		if !token.Valid { //Token is invalid, maybe not signed on this server
			response = u.Message(false, "Token is not valid.")
			w.WriteHeader(http.StatusForbidden)
			w.Header().Add("Content-Type", "application/json")
			u.Respond(w, response)
			return
		}

		//Everything went well, proceed with the request and set the caller to the user retrieved from the parsed token
		fmt.Sprintf("User %", tk.Username) //Useful for monitoring
		ctx := context.WithValue(r.Context(), "user", tk.UserId)
		r = r.WithContext(ctx)
		next.ServeHTTP(w, r) //proceed in the middleware chain!
	});
}
```

The comments inside the code explain everything there is to know, but basically, the code create a Middleware to intercept every requests, check for the presence of an authentication token (JWT token), verify if it is authentic and valid, then send error back to the client if we detect any deficiency in the token or proceed to serving the request otherwise(if the token is valid), you’ll see later, how we can access the user that is interacting with our API from the request.

### Building the user registration and login system

We want our users to be able to register and login before backing up/storing their contacts on our system. The first thing we will need to do is connect to our database, we use a .env file to store our database credentials, my .env looks like this

    db_name = gocontacts
    db_pass = **** //This is default to the current user's password on windows for postgresql
    db_user = postgres
    db_type = postgres
    db_host = localhost
    db_port = 5434
    token_password = thisIsTheJwtSecretPassword //Do not commit to git!

Then, we can connect to the database using the following snippets

```go
package models

import (
	_ "github.com/jinzhu/gorm/dialects/postgres"
	"github.com/jinzhu/gorm"
	"os"
	"github.com/joho/godotenv"
	"fmt"
)

var db *gorm.DB //database

func init() {

	e := godotenv.Load() //Load .env file
	if e != nil {
		fmt.Print(e)
	}

	username := os.Getenv("db_user")
	password := os.Getenv("db_pass")
	dbName := os.Getenv("db_name")
	dbHost := os.Getenv("db_host")


	dbUri := fmt.Sprintf("host=%s user=%s dbname=%s sslmode=disable password=%s", dbHost, username, dbName, password) //Build connection string
	fmt.Println(dbUri)

	conn, err := gorm.Open("postgres", dbUri)
	if err != nil {
		fmt.Print(err)
	}

	db = conn
	db.Debug().AutoMigrate(&Account{}, &Contact{}) //Database migration
}

//returns a handle to the DB object
func GetDB() *gorm.DB {
	return db
}
```

The code does a very simple thing, on the file init() function — init() automatically get called by Go, the code retrieve connection information from .env file then build a connection string and use it to connect to the database.

### Creating the application entry point

So far, we’ve been able to create the JWT middleware and connect to our database. The next thing is creating the application’s entry point, see the code snippet below

```go
package main

import (
	"github.com/gorilla/mux"
	"go-contacts/app"
	"os"
	"fmt"
	"net/http"
)

func main() {

	router := mux.NewRouter()
	router.Use(app.JwtAuthentication) //attach JWT auth middleware

	port := os.Getenv("PORT") //Get port from .env file, we did not specify any port so this should return an empty string when tested locally
	if port == "" {
		port = "8000" //localhost
	}

	fmt.Println(port)

	err := http.ListenAndServe(":" + port, router) //Launch the app, visit localhost:8000/api
	if err != nil {
		fmt.Print(err)
	}
}
```

We create a new Router object — line 13, we attach our JWT auth middleware using router’s Use() function — line 14, and then we proceed to start listening for incoming requests.

![](https://cdn-images-1.medium.com/max/2000/1*O_eTZ7RGS0uxNHpfmKPORA.png)

Use the small media play button located left of func main() to compile and launch the app, if all is good, you should see no error in the console, in case there was an error, take a second look at your database connection parameters to see that they correlate.

![Results. DB migrations has occurred, GORM converted go struct to database tables](https://cdn-images-1.medium.com/max/2732/1*Fdq9mK_pk92jfB8YjF5qgw.png)*Results. DB migrations has occurred, GORM converted go struct to database tables*

### Creating and authenticating Users

create a new file models/accounts.go,

```go
package models

import (
	"github.com/dgrijalva/jwt-go"
	u "lens/utils"
	"strings"
	"github.com/jinzhu/gorm"
	"os"
	"golang.org/x/crypto/bcrypt"
)

/*
JWT claims struct
*/
type Token struct {
	UserId uint
	jwt.StandardClaims
}

//a struct to rep user account
type Account struct {
	gorm.Model
	Email string `json:"email"`
	Password string `json:"password"`
	Token string `json:"token";sql:"-"`
}

//Validate incoming user details...
func (account *Account) Validate() (map[string] interface{}, bool) {

	if !strings.Contains(account.Email, "@") {
		return u.Message(false, "Email address is required"), false
	}

	if len(account.Password) < 6 {
		return u.Message(false, "Password is required"), false
	}

	//Email must be unique
	temp := &Account{}

	//check for errors and duplicate emails
	err := GetDB().Table("accounts").Where("email = ?", account.Email).First(temp).Error
	if err != nil && err != gorm.ErrRecordNotFound {
		return u.Message(false, "Connection error. Please retry"), false
	}
	if temp.Email != "" {
		return u.Message(false, "Email address already in use by another user."), false
	}

	return u.Message(false, "Requirement passed"), true
}

func (account *Account) Create() (map[string] interface{}) {

	if resp, ok := account.Validate(); !ok {
		return resp
	}

	hashedPassword, _ := bcrypt.GenerateFromPassword([]byte(account.Password), bcrypt.DefaultCost)
	account.Password = string(hashedPassword)

	GetDB().Create(account)

	if account.ID <= 0 {
		return u.Message(false, "Failed to create account, connection error.")
	}

	//Create new JWT token for the newly registered account
	tk := &Token{UserId: account.ID}
	token := jwt.NewWithClaims(jwt.GetSigningMethod("HS256"), tk)
	tokenString, _ := token.SignedString([]byte(os.Getenv("token_password")))
	account.Token = tokenString

	account.Password = "" //delete password

	response := u.Message(true, "Account has been created")
	response["account"] = account
	return response
}

func Login(email, password string) (map[string]interface{}) {

	account := &Account{}
	err := GetDB().Table("accounts").Where("email = ?", email).First(account).Error
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			return u.Message(false, "Email address not found")
		}
		return u.Message(false, "Connection error. Please retry")
	}

	err = bcrypt.CompareHashAndPassword([]byte(account.Password), []byte(password))
	if err != nil && err == bcrypt.ErrMismatchedHashAndPassword { //Password does not match!
		return u.Message(false, "Invalid login credentials. Please try again")
	}
	//Worked! Logged In
	account.Password = ""

	//Create JWT token
	tk := &Token{UserId: account.ID}
	token := jwt.NewWithClaims(jwt.GetSigningMethod("HS256"), tk)
	tokenString, _ := token.SignedString([]byte(os.Getenv("token_password")))
	account.Token = tokenString //Store the token in the response

	resp := u.Message(true, "Logged In")
	resp["account"] = account
	return resp
}

func GetUser(u uint) *Account {

	acc := &Account{}
	GetDB().Table("accounts").Where("id = ?", u).First(acc)
	if acc.Email == "" { //User not found!
		return nil
	}

	acc.Password = ""
	return acc
}
```

There is a lot of puzzle inside accounts.go, lets break it down a little bit.

The first part create two structs Token and Account they represent a JWT token claim and a user account respectively. Function Validate() validates the data sent from clients and function Create() creates a new account and generate a JWT token that will be sent back to client that made the request. Function Login(username, password) authenticate an existing user, then generate a JWT token if authentication was successful.

**authController.go**

```go
package controllers

import (
	"net/http"
	u "go-contacts/utils"
	"go-contacts/models"
	"encoding/json"
)

var CreateAccount = func(w http.ResponseWriter, r *http.Request) {

	account := &models.Account{}
	err := json.NewDecoder(r.Body).Decode(account) //decode the request body into struct and failed if any error occur
	if err != nil {
		u.Respond(w, u.Message(false, "Invalid request"))
		return
	}

	resp := account.Create() //Create account
	u.Respond(w, resp)
}

var Authenticate = func(w http.ResponseWriter, r *http.Request) {

	account := &models.Account{}
	err := json.NewDecoder(r.Body).Decode(account) //decode the request body into struct and failed if any error occur
	if err != nil {
		u.Respond(w, u.Message(false, "Invalid request"))
		return
	}

	resp := models.Login(account.Email, account.Password)
	u.Respond(w, resp)
}
```

The content is very straightforward. It contains the handler for /user/new and /user/login endpoints.

Add the following snippet to main.go to register our new routes

    router.HandleFunc(**"/api/user/new"**, controllers.CreateAccount).Methods(**"POST"**)

    router.HandleFunc(**"/api/user/login"**, controllers.Authenticate).Methods(**"POST"**)

The above code register both /user/new and /user/login endpoints and pass their corresponding request handlers.

Now, recompile the code and visit localhost:8000/api/user/new using postman, set the request body to application/json as shown below

![Response from /user/new](https://cdn-images-1.medium.com/max/2732/1*yzjtBq5zMPrgy0GN5sQKng.png)*Response from /user/new*

If you try to call /user/new twice with the same payload, you’ll receive a response that the email already exists, works according to our instructions.

### Creating contacts

Part of our app’s functionality is letting our users create/store contacts. Contact will have name and phone , we will define these as struct properties. The following snippets belongs to models/contact.go

```go
package models

import (
	u "go-contacts/utils"
	"github.com/jinzhu/gorm"
	"fmt"
)

type Contact struct {
	gorm.Model
	Name string `json:"name"`
	Phone string `json:"phone"`
	UserId uint `json:"user_id"` //The user that this contact belongs to
}

/*
 This struct function validate the required parameters sent through the http request body
returns message and true if the requirement is met
*/
func (contact *Contact) Validate() (map[string] interface{}, bool) {

	if contact.Name == "" {
		return u.Message(false, "Contact name should be on the payload"), false
	}

	if contact.Phone == "" {
		return u.Message(false, "Phone number should be on the payload"), false
	}

	if contact.UserId <= 0 {
		return u.Message(false, "User is not recognized"), false
	}

	//All the required parameters are present
	return u.Message(true, "success"), true
}

func (contact *Contact) Create() (map[string] interface{}) {

	if resp, ok := contact.Validate(); !ok {
		return resp
	}

	GetDB().Create(contact)

	resp := u.Message(true, "success")
	resp["contact"] = contact
	return resp
}

func GetContact(id uint) (*Contact) {

	contact := &Contact{}
	err := GetDB().Table("contacts").Where("id = ?", id).First(contact).Error
	if err != nil {
		return nil
	}
	return contact
}

func GetContacts(user uint) ([]*Contact) {

	contacts := make([]*Contact, 0)
	err := GetDB().Table("contacts").Where("user_id = ?", user).Find(&contacts).Error
	if err != nil {
		fmt.Println(err)
		return nil
	}

	return contacts
}
```

Same as in models/accounts.go we create a function Validate() to validate the passed inputs, we return an error with messages if anything we don’t want occur, then we wrote function Create() to insert this contact into the database.

The only part left is retrieving the contacts. Lets do it!

    router.HandleFunc(**"/api/me/contacts"**, controllers.GetContactsFor).Methods(**"GET"**)

Add the above snippet to main.go to tell the router to register /me/contacts
endpoint. Lets create controllers.GetContactsFor handler to handle the API request.

**contactsController.go**

Bellow is the content of contactsController.go

```go
package controllers

import (
	"net/http"
	"go-contacts/models"
	"encoding/json"
	u "go-contacts/utils"
	"strconv"
	"github.com/gorilla/mux"
	"fmt"
)

var CreateContact = func(w http.ResponseWriter, r *http.Request) {

	user := r.Context().Value("user") . (uint) //Grab the id of the user that send the request
	contact := &models.Contact{}

	err := json.NewDecoder(r.Body).Decode(contact)
	if err != nil {
		u.Respond(w, u.Message(false, "Error while decoding request body"))
		return
	}

	contact.UserId = user
	resp := contact.Create()
	u.Respond(w, resp)
}

var GetContactsFor = func(w http.ResponseWriter, r *http.Request) {

	params := mux.Vars(r)
	id, err := strconv.Atoi(params["id"])
	if err != nil {
		//The passed path parameter is not an integer
		u.Respond(w, u.Message(false, "There was an error in your request"))
		return
	}
	
	data := models.GetContacts(uint(id))
	resp := u.Message(true, "success")
	resp["data"] = data
	u.Respond(w, resp)
}
```

What it does is pretty similar to authController.go's , but basically, it grabs the json body and decode it into Contact struct, if there was an error, return a response immediately or insert the contacts into the database if everything went well.

**Fetching Contacts that belongs to a user**

Now, our users have been able to store their contacts successfully, what if they want to retrieve the contact they stored, in case their phone is lost? Visiting /me/contacts should return a json structure for the contacts of the API caller(current user). Check the code snippet to have a clearer picture.

Normally, retrieving user’s contacts endpoint should look like /user/{userId}/contacts , specifying userId as a path parameter is very dangerous, because every authenticated user can craft a request to this path and contacts of another users would be returned without any problem, this can lead to a brutal attack by hackers — I am trying to point out the usefulness of JWT .
We can easily obtain the id of the API caller using r.Context().Value("user") , remember we set this value inside auth.go — Our authentication middleware

```go
package controllers

import (
	"net/http"
	"go-contacts/models"
	"encoding/json"
	u "go-contacts/utils"
	"strconv"
	"github.com/gorilla/mux"
	"fmt"
)

var CreateContact = func(w http.ResponseWriter, r *http.Request) {

	user := r.Context().Value("user") . (uint) //Grab the id of the user that send the request
	contact := &models.Contact{}

	err := json.NewDecoder(r.Body).Decode(contact)
	if err != nil {
		u.Respond(w, u.Message(false, "Error while decoding request body"))
		return
	}

	contact.UserId = user
	resp := contact.Create()
	u.Respond(w, resp)
}

var GetContactsFor = func(w http.ResponseWriter, r *http.Request) {

	params := mux.Vars(r)
	id, err := strconv.Atoi(params["id"])
	if err != nil {
		//The passed path parameter is not an integer
		u.Respond(w, u.Message(false, "There was an error in your request"))
		return
	}
	
	data := models.GetContacts(uint(id))
	resp := u.Message(true, "success")
	resp["data"] = data
	u.Respond(w, resp)
}
```

![Response for /me/contacts](https://cdn-images-1.medium.com/max/2732/1*NMXFN6aCXqoIiM5FSB2qIQ.png)*Response for /me/contacts*

The code for this project is on github — [https://github.com/adigunhammedolalekan/go-contacts](https://github.com/adigunhammedolalekan/go-contacts)

## Deployment

We can easily deploy our app to heroku. Firstly, download godep . godep is a dependency manager for Golang, similar to npm for nodejs.

    go get -u github.com/tools/godep

* Open GoLand terminal and run godep save This will create a folder call Godeps and vender . To learn more about godep, visit [https://github.com/tools/godep](https://github.com/tools/godep)

* Create account on heroku.com and download Heroku Cli then login with your credentials

* Once done, run heroku create gocontacts This will create an app for you on your heroku dashboard and also a remote git repository.

* run the following command to push your code to heroku

* git add .

* git commit -m "First commit"

* git push heroku master

![](https://cdn-images-1.medium.com/max/2732/1*w9Vm0lZANuGCzQGbNuunDQ.png)

If everything went well, your screen should look like my own.

Voila! Your app has been deployed. The next thing is setting up a remote Postgresql database.

run heroku addons:create heroku-postgresql:hobby-dev to create the database. To learn more about this, visit [https://devcenter.heroku.com/articles/heroku-postgresql](https://devcenter.heroku.com/articles/heroku-postgresql)

Great! We are almost there, next thing is to connect with our remote database.

Go to heroku.com and login with your credentials, you should find your newly created app on your dashboard, click on it. After that, click on settings, then click on Reveal Config Vars 
Postgresql connection URI format postgres://username:password@host/dbName , There is a var named DATABASE_URL , this was automatically added to your .env file when you created the postgresql database (Note: Heroku automatically replace your local .env when you deploy your app), from this var, we will extract our database connection parameter.

![](https://cdn-images-1.medium.com/max/2732/1*rS24jUlHUgjnIb_F2IFtXw.png)

![I extracted database connection parameter from the auto generated DATABASE_URL vars](https://cdn-images-1.medium.com/max/2732/1*fw5kKwbwOxy91Xjpjbzw4A.png)*I extracted database connection parameter from the auto generated DATABASE_URL vars*

If all this went well, your API should be live now!

![As you can see, the api is live!](https://cdn-images-1.medium.com/max/2732/1*nOTRa077OtAWIWk9ApwTFg.png)*As you can see, the api is live!*

I tried my best to make this lesson clear as much as possible. Please, bear with me for any error you might encountered. I am just trying to share my knowledge.

Project Repo — [https://github.com/adigunhammedolalekan/go-contacts](https://github.com/adigunhammedolalekan/go-contacts)

If you have any question, or a correction, i will be glad to know.

Follow me on Twitter — [www.twitter.com/L3kanAdigun](http://www.twitter.com/L3kanAdigun)

Hire me(I am available and actively looking for job, DM me on Twitter) —[www.twitter.com/L3kanAdigun](http://www.twitter.com/L3kanAdigun)

You can mail me personally — adigunhammed.lekan@gmail.com

Its really a long article, Thanks for reading.
