---
title: "Building Docker Images Dynamically with Go"
date: 2019-08-22 00:00:00 +0000
draft: false
---

I recently started looking into ways of automating microservices app deployment and one of the many things i needed to automate is the famous docker build command. I understand that i could take advantage of the installed Docker client on the host computer by using os/exec package, but my idea isn’t that simple and its not really fun compared to using github.com/docker/docker/client — refer to as goDockerClient henceforth. This post contains the steps i followed to building docker images successfully with goDockerClient

### Understand the Docker BuildContext

After i spent some time checking out goDockerClient [GoDoc](https://godoc.org/github.com/docker/docker/client), i felt like i was ready to start building docker images dynamically but i was wrong. It wasn’t as trivial as the Doc made it look, i thought all i had to do was call client.ImageBuild(context.Context, buildContext, opts) specifying my Dockerfile in opts.Dockerfile , after few unsuccessful trials, i began digging deeper. Turns out buildContext which is of type io.Reader is suppose to be the content of the image i am trying to build. Initially, i was doing something like this

```go
func createBuildContext() (io.Reader, error) {
  // get current working dir
  wd, err := os.Getwd()
  if err != nil {
    return nil, err
  }
  // resolve Dockerfile path
  path := filepath.join(wd, "Dockerfile")
  return os.Open(path)
}
```
Using just the Dockerfile as buildContext will not work because the docker daemon expect the buildContext to be all the files you’ll need in your new docker image.

### What worked

After understanding what docker meant by buildContext the task at hand became easier. We just need a way to wrap all the files in a dir — BuildContext into an io.Reader so that we can easily send this to docker deamon and have our image built. Luckily, there is a helper function in goDockerClient that does just this, just give it a directory and this function would tar it and give you an io.Reader .

```go
import "github.com/docker/docker/pkg/archive"

// createBuildContext archive a dir and return an io.Reader
func createBuildContext(path string) (io.Reader, error) {
	return archive.Tar(path, archive.Uncompressed)
}
```

The final solution. The code below results to a successful dynamic docker build

```go
// buildLocalImage build a docker image from the supplied `path` parameter.
// The image built is intended to be pushed to a local docker registry.
// This function assumes there is a Dockerfile in the dir
func buildLocalImage(path string) error {
  // get current working dir, to resolve the path to Dockerfile
  wd, err := os.Getwd()
  if err != nil {
     return err
  }

  // create a docker buildContext by `archiving` the files
  // the target dir
  buildCtx, err := createBuildContext(path)
  if err != nil {
     return err
  }

  // form a unique docker tag. the first string seg is the local docker registry host
  tag := fmt.Sprintf("%s%s%s", "docker-registry:5000/", build.Name(), p.md5()[:6])
  ctx := context.Background()
  // build image. reader can be used to get output from docker deamon
  reader, err := p.client.ImageBuild(ctx, buildCtx, types.ImageBuildOptions{
     Dockerfile: "Dockerfile", PullParent: true, Tags: []string{tag}, Remove: true, NoCache: true,
  })
  if err != nil {
     return err
  }

  for {
	buf := make([]byte, 512)
	_, err := reader.Body.Read(buf)
	if err != nil {
	   if err == io.EOF {
		break
	    }
	    log.Println("error reading response ", err)
	    continue
	}
	// print outputs
  	log.Println(string(buf[:]))
   }
  // yay! no errors
  return nil
}
```

Full code gist can be found here — [https://gist.github.com/adigunhammedolalekan/354f31e7f9b53e6c76d09b2247d3ecad](https://gist.github.com/adigunhammedolalekan/354f31e7f9b53e6c76d09b2247d3ecad)

Thank you.
