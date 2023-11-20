$_defaultFadeoutTaskName = "Fadeout"

function Start-Fadeout {
    param(
        $taskName = $_defaultFadeoutTaskName
    )

    Start-ScheduledTask -TaskName $taskName
}

function Stop-Fadeout {
    param(
        $taskName = $_defaultFadeoutTaskName
    )

    Stop-ScheduledTask -TaskName $taskName
}

Export-ModuleMember -Function Start-Fadeout, Stop-Fadeout

