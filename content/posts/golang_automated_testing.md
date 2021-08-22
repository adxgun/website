---
title: "Unit Testing REST Services in Go"
date: 2021-08-22 00:00:00 +0000
draft: false
---
Building software is a complex process. A software project perceived to be simple when started can easily grow to having thousands of lines of code. Also, unforeseen circumstances are common occurrence for any software project and this can cause a lot of unplanned changes. Making changes to a software can be very hard and unpredictable, especially when it is not done carefully, there has been many real life instances where numerous problems or bugs were introduce to a software due to some changes made to it. This is also known as regression bug - a bug introduced as a result of a change or changes in a system. 
Writing automated tests is a great solution to minimising regression bug. Alongside with preventing regression bug, here are some other benefits of automated testing.

* Enhance fast iterable feature development.
* Faster & more accurate - Can you manually test 100s of HTTP endpoints in secs? Test automation can!
* Easier code improvement & maintainability


Of course, you can read more about the numerous benefits you can acquire by writing automated tests - https://www.testim.io/blog/test-automation-benefits/


One aspect of software development cycle where there's less learning resources is automated testing. I personally had problems understanding why automated testing is needed and most importantly, how to do it right. Why i have to write code to test my code? Sounds elegant but some things don't really make sense until you see how much values they bring. 


In this article, we're going to see how to write automated tests for Go REST services. Hopefully, someone out there would find it useful!

#### Assumptions
I assume you have basic knowledge of how HTTP request & response works, Golang knowledge is not essential as you can apply the principles in other languages, although many Golang specific library and semantics are used, it shouldn't be too hard to take the principles and use them in other programming environments.

### So what are Unit tests?
Before we dive in, i think it's important to understand what Unit tests are. A Unit test is similar to what the name suggests, it is written to test a unit section or function in a particular software program, it is done to make sure a unit/function in a program behaves as expected, it is often written to mimic multiple scenario ensuring the program unit behaves as expected when tested under all these scenarios. One important characteristics of Unit tests is `Speed`. Unit tests should
run very quickly because the programmer would run them multiple time during the course of programming and development.

### The `net/http/httptest` Package
The Go standard library does not only provide rich packages to write http servers but it also provide rich packages to test them. The best place to look when looking to test REST services in Go is in the `net/http/httptest` package. It provides a hassle free components to test http handlers. As we'll soon see, this package provide a way to create `http.Request` and `http.ResponseWriter` object which are important parts of any Go http handler. You can read more about this package [HERE - GoDoc](https://pkg.go.dev/net/http/httptest) 

### Golang Interfaces
*Don't worry - I am not moving away from our topic.* Interfaces in Golang are very essential when writing tests - especially unit tests. They provide an excellent way to abstract concrete implementation of a logical function. Consider an example below:


```go
type Greeter interface {
    Greet(name string) (string, error)
}

type realGreeter struct {
    c RestClient
} 
func (r *realGreeter) Greet(name string) (string, error) {
    if r.c.Authorized(name) {
        return "Hello " + name, nil
    }
    return "", errors.New("You're not allowed to be greeted")
}

type fakeGreeter struct {}
func (r *fakeGreeter) Greet(name string) (string, error) {
   return "Hi, Mr. " + name
}

type GreeterEngine struct {
    greeter Greeter
}

func main() {
    env := os.Getenv("ENV")
    g := &realGreeter{}
    if env == "local" {
        g = &fakeGreeter{}
    }
    engine := &GreeterEnginer{greeter: g}
    r, err := engine.greeter.Greet("Robot")
    assert.Nil(err)
    assert.Equals(r, "Hi, Mr. Robot")
}
```

Long piece of code, i know and i wish i could make it shorter :(

The main point to be noted in the code snippet above is how we switch the implementation of a `Greeter` in a `GreeterEngine` based on the environment our code is executed in. This is a very useful trick when writing test, `Unit test` is about control - you should be able to control scenarios and outcomes because that is how you get power to test your systems as you see fit. The above example can also be related to a real life case where you can switch a real implementation of 
a function(e.g a function that makes HTTP or database calls as part of it operation) to a fake function(e.g a function that mocks HTTP or database calls). As we'll soon see later in this post, interfaces are used heavily when mocking service dependencies which is one of the most important aspect of unit testing.


### Mocking
Mocking is creating objects and functions that simulates or mimic the behavior of real objects/functions. REST services code structures are often complex with many dependencies. One of the best way to isolate these dependencies without too much hassles and unnecessary resources wasting is mocking. Let's assume you need to test an API endpoint that accepts user details, performs data transformation and finally, persist the data. Your responsibility as a unit tester is to make sure you successfully accept, process and make calls to the database to persist the data, whether database connection succeeds or not is NOT your responsibility which is why you would `mock` this aspect. Unit testing is also about assumption, putting it mildly -- **Assuming database connection state is X, then API behavior should be Y** 

Enough talking, show me the code!


## An Example
We are going ahead to create a simple sample project to demonstrate testing REST services. We want a simple system that creates blog posts via an endpoint plus another endpoint that retrieves the created posts -- we are picking a well understood example simply because it'll allow us focus more on how unit testing works rather than the example project itself.

Let's dive in!   

Quickly download and open the completed code for this project. It is hosted on [GITHUB](https://github.com/adigunhammedolalekan/rest-services-testing)

We will first take a quick overview of the external packages we'll be using in this project. Below is a list and a brief explanation of what each package is used for in this sample project.

* chi [Github](https://github.com/go-chi/chi) - `Github:` lightweight, idiomatic and composable router for building Go HTTP services. Like we've seen in the description, we use this package to create our REST service.
* testify [Github](https://github.com/stretchr/testify) - `Github: `A toolkit with common assertions and mocks that plays nicely with the standard library. -- This is used in this example to facilitate easy testing.
* gomock [Github](github.com/golang/mock) - `Github: ` GoMock is a mocking framework for the Go programming language. An initial setup steps is required to use GoMock, latest installation instruction can be found [HERE](https://github.com/golang/mock) -- This package is used to mock test dependencies.

```go
package handlers

import (
	"encoding/json"
	"github.com/adigunhammedolalekan/rest-unit-testing-sample/repository"
	"github.com/go-chi/render"
	"net/http"
)

type Handler struct {
	repo repository.Repository
}

func New(repo repository.Repository) *Handler {
	return &Handler{repo: repo}
}

func (handler *Handler) CreatePostHandler(w http.ResponseWriter, r *http.Request) {
	var body struct{
		Title string `json:"title"`
		Body string `json:"body"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		render.Status(r, http.StatusBadRequest)
		render.Respond(w, r, &response{Success: false, Message: "malformed body"})
		return
	}

	token := r.Header.Get("x-auth-token")
	user, err := handler.repo.GetUser(token)
	if err != nil {
		render.Status(r, http.StatusForbidden)
		render.Respond(w, r, &response{Success: false, Message: "forbidden"})
		return
	}

	p, err := handler.repo.CreatePost(user.ID.String(), body.Title, body.Body)
	if err != nil {
		render.Status(r, http.StatusInternalServerError)
		render.Respond(w, r, &response{Success: false, Message: "server error"})
		return
	}
	render.Status(r, http.StatusOK)
	render.Respond(w, r, &response{Success: true, Message: "post.created", Data: p})
}
```

The code block above contains an http handler - `CreatePostHandler`. This handler is self explanatory but let's see a detailed explanation below.

Line 19-22 defined a temporary struct to hold a Post data sent by a client. Line 23-27 decodes the request's JSON body into our defined temp struct, this will return a `400 - Badrequest` error when a malformed or non-JSON body is detected. Line 29-35 performs authorization check to ensure the user that's about to create a post is allowed to do so. In this example, we used a fictional authentication and authorization system in order to keep the example simple and not take our eyes off the goal. And, finally Line 37-45 send the new Post to a persistence layer, error is returned if there were problems while interacting with the persistence layer or a success message is returned otherwise. 

Let's look at how to test this handler.   

First step is to generate mocks for our persistence layer, i explained previously how dependent services needs to be mocked in other to have control and test our service as we see fit -- which is exactly what we are going to do here because database is a service we depend on. For this purpose, we will be using `GoMock`.   

Change to the project root directory and run the command below(assuming you installed `mockgen`):   
```shell script
mockgen -source=repo.go -destination=../mocks/repository_mock.go -package=mocks
```

The above command will generate mock implementations for `repository/repo.go` and put them in `mocks` directory/package. We will be using the generated code to mock our database dependency.   

We'll go ahead and separate our test code into three main parts - `arrange`, `act` and `assert`, this is a common pattern considered to be the best way to write good tests. Let's take advantage of it!   

Before that, let's take a look at steps involved in each stage.   

* Create an implementation of `http.ResponseWriter` provided to us by the `net/http/httptest` package. And, create a new mock Controller.
```go
w := httptest.NewRecorder()
ctrl := gomock.NewController(t)
defer ctrl.Finish()

```   
* Setup a mock http request, you can customize this request according to your test need. In this project, We simply added a dummy Post{} object in the body of the request, we also added a mock authorization token to satisfy the requirement for our 'Fictional' auth and authz system.
```go
    type body struct{
		Title string `json:"title"`
		Body string `json:"body"`
	}

	mockToken := uuid.New().String()
	mockPost := &body{Title: "Test Title", Body: "Test Body"}
	mockUser := &types.User{ID: uuid.New(), Name: "Tester"}
	buf := &bytes.Buffer{}
	err := json.NewEncoder(buf).Encode(mockPost)
	assert.Nil(t, err)

	r := httptest.NewRequest("POST", "/", buf)
	r.Header.Add("x-auth-token", mockToken)
```
* Create mock instance for `Repository` -- which represents our persistence layer that we're specifically interested in mocking out. Also, set expectations. Setting expectations is how we make sure nothing else happens except for what we've actually written in our http handler. It is also a way to control our mock, tell it what input to expect, how many times it is expected to be called and set an output. This aspect can be a little bit confusing but it's very key to writing good unit tests for http handlers.

```go
    repo := mocks.NewMockRepository(ctrl)
	repo.EXPECT().GetUser(mockToken).Return(mockUser, nil).Times(1)
	repo.EXPECT().CreatePost(mockUser.ID.String(), mockPost.Title, mockPost.Body).Return(&types.Post{}, nil).Times(1)
```

* Execute handler and assert expectations. This is where we execute our http handler -- `In a non-test context, this is equivalent to making http request to our handler`. We also check if we have expected http statuscode and response body -- This makes sense because this is what our users would do. By making sure we have the expected/correct statuscode, we've effectively tested this http handler.
```go
    handler := New(repo)
	handler.CreatePostHandler(w, r)

    assert.Equal(t, http.StatusOK, w.Code)
    assert.True(t, strings.Contains(w.Body.String(), "post.created"))
```

Putting it all together,   

```go

func TestHandler_CreatePostHandler(t *testing.T) {

    // arrange
	w := httptest.NewRecorder()
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	type body struct{
		Title string `json:"title"`
		Body string `json:"body"`
	}

	mockToken := uuid.New().String()
	mockPost := &body{Title: "Test Title", Body: "Test Body"}
	mockUser := &types.User{ID: uuid.New(), Name: "Tester"}
	buf := &bytes.Buffer{}
	err := json.NewEncoder(buf).Encode(mockPost)
	assert.Nil(t, err)

	r := httptest.NewRequest("POST", "/", buf)
	r.Header.Add("x-auth-token", mockToken)

	repo := mocks.NewMockRepository(ctrl)
	repo.EXPECT().GetUser(mockToken).Return(mockUser, nil).Times(1)
	repo.EXPECT().CreatePost(mockUser.ID.String(), mockPost.Title, mockPost.Body).Return(&types.Post{}, nil).Times(1)

    // act
	handler := New(repo)
	handler.CreatePostHandler(w, r)
    
    // assert
	assert.Equal(t, http.StatusOK, w.Code)
	assert.True(t, strings.Contains(w.Body.String(), "post.created"))
}
```

Full code, including the 2nd endpoint(to get created posts) and it test can be found in the [LINKED](https://github.com/adigunhammedolalekan/rest-services-testing) github repository.  

Thanks for reading. I am actively taking feedback via email or my [Twitter DM](https://twitter.com/@L3kanAdigun).   

Happy coding :)
