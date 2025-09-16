pub mod error {
    use thiserror::*;
    use windows::core;
    
    pub type PublisherError = core::Error;
    
    #[derive(Debug, Error)]
    pub enum WinError {
        #[error("Publisher error: {0}.")]
        Publisher(#[from] PublisherError),
    }
}

use windows::{
    Devices::{Enumeration::*, WiFiDirect::*},
    Networking::Sockets::*,
    Storage::Streams::*,
    Foundation::TypedEventHandler,
};
use crate::common::Publisher;

pub type WinPublisher = WiFiDirectAdvertisementPublisher;
impl Publisher for WinPublisher {
    type Error = error::WinError;

    #[inline(always)]
    fn start(&self) -> Result<(), Self::Error> {
        self.Start()?;
        Ok(())
    }

    #[inline(always)]
    fn stop(&self) -> Result<(), Self::Error> {
        self.Stop()?;
        Ok(())
    }
}

pub async fn test() -> Result<(), Box<dyn std::error::Error>> {
    let publisher = WiFiDirectAdvertisementPublisher::new()?;
    publisher.Start()?;
    let add = publisher.Advertisement()?;
    let status = publisher.Status()?;
    println!("{add:?}");
    println!("{status:?}");
    
    loop {
        let selector = WiFiDirectDevice::GetDeviceSelector()?;
        let devices = DeviceInformation::FindAllAsyncAqsFilter(&selector)?.await?;
        
        for device in devices {
            println!("Name: {}, Id: {}", device.Name()?, device.Id()?);
        }
    }

    Ok(())
}