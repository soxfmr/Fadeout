$_defaultFadeoutTaskName = "Fadeout"

function Start-Fadeout {
    param(
        $taskName = $_defaultFadeoutTaskName
    )

    Start-ScheduledTask -TaskName $taskName -AsJob
}

function Stop-Fadeout {
    param(
        $taskName = $_defaultFadeoutTaskName
    )

    Stop-ScheduledTask -TaskName $taskName -AsJob
}
