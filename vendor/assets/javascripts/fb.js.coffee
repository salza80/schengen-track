class @Facebook

    rootElement = null
    eventsBound = false

    @load: ->
        unless $('#fb-root').size() > 0
            initialRoot = $('<div>').attr('id', 'fb-root')
            $('body').prepend initialRoot

        unless $('#facebook-jssdk').size() > 0
            facebookScript = document.createElement("script")
            facebookScript.id = 'facebook-jssdk'
            facebookScript.async = 1
            facebookScript.src = "//connect.facebook.net/en_US/sdk.js#xfbml=1&version=v2.5&appId=1666941640196067"

            firstScript = document.getElementsByTagName("script")[0]
            firstScript.parentNode.insertBefore facebookScript, firstScript

        Facebook.bindEvents() unless Facebook.eventsBound

    @bindEvents = ->
        if typeof Turbolinks isnt 'undefined' and Turbolinks.supported
            $(document)
                .on('page:fetch', Facebook.saveRoot)
                .on('page:change', Facebook.restoreRoot)
                .on('page:load', ->
                    FB?.XFBML.parse()
                )

        Facebook.eventsBound = true

    @saveRoot = ->
        Facebook.rootElement = $('#fb-root').detach()

    @restoreRoot = ->
        if $('#fb-root').length > 0
            $('#fb-root').replaceWith Facebook.rootElement
        else
            $('body').append Facebook.rootElement

    @appId = ->
        '1666941640196067'

Facebook.load()
