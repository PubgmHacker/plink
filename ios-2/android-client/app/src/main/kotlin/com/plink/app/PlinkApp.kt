package com.plink.app

import android.app.Application
import com.plink.app.di.AppContainer

class PlinkApp : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
    }
}